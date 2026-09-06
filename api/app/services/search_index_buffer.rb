# Coalesces Meili reindex work so scan / cover / curation / creator bursts
# cannot enqueue one IndexVibeModelJob per model (or per after_commit).
# Unique model ids sit in a set; one BulkIndexVibeModelsJob drains them.
class SearchIndexBuffer
  PENDING_KEY = "vibe:search:index:pending"
  FLUSH_KEY = "vibe:search:index:flush"

  class << self
    def add(id)
      add_ids([id])
    end

    def add_ids(ids)
      normalized = Array(ids).filter_map { |id| normalize_id(id) }
      return if normalized.empty?

      backend.add_ids(normalized)
      schedule!
    end

    def drain(limit = SearchIndex.batch_size)
      backend.drain(limit)
    end

    def pending_ids
      backend.pending_ids
    end

    def pending?
      backend.pending?
    end

    def schedule!(wait: SearchIndex.debounce_seconds)
      return unless pending?
      return unless backend.claim_flush!(ttl: flush_claim_ttl(wait))

      delay = wait.to_f
      if delay <= 0
        BulkIndexVibeModelsJob.perform_later
      else
        BulkIndexVibeModelsJob.set(wait: delay).perform_later
      end
    end

    def schedule_if_pending!
      schedule!(wait: 0)
    end

    def release_flush!
      backend.release_flush!
    end

    def reset!
      backend.reset!
      @backend = nil if Rails.env.test?
    end

    def backend
      @backend ||= connect_backend
    end

    private

    def normalize_id(id)
      value = id.respond_to?(:id) ? id.id : id
      return if value.blank?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def flush_claim_ttl(wait)
      [wait.to_i + 15, 20].max
    end

    def connect_backend
      return MemoryBackend.new if Rails.env.test?

      url = ENV["REDIS_URL"].presence || "redis://127.0.0.1:6379/0"
      redis = Redis.new(url: url, timeout: 0.2, connect_timeout: 0.2)
      redis.ping
      RedisBackend.new(redis)
    rescue StandardError => e
      Rails.logger.warn("[SearchIndexBuffer] Redis unavailable (#{e.class}: #{e.message}); in-process debounce only")
      MemoryBackend.new
    end
  end

  class MemoryBackend
    def initialize
      @lock = Mutex.new
      @pending = Set.new
      @flush_claimed = false
    end

    def add_ids(ids)
      @lock.synchronize { ids.each { |id| @pending << id } }
    end

    def drain(limit)
      @lock.synchronize do
        taken = @pending.to_a.first(limit)
        taken.each { |id| @pending.delete(id) }
        taken
      end
    end

    def pending_ids
      @lock.synchronize { @pending.to_a }
    end

    def pending?
      @lock.synchronize { @pending.any? }
    end

    def claim_flush!(ttl:)
      @lock.synchronize do
        return false if @flush_claimed

        @flush_claimed = true
        true
      end
    end

    def release_flush!
      @lock.synchronize { @flush_claimed = false }
    end

    def reset!
      @lock.synchronize do
        @pending.clear
        @flush_claimed = false
      end
    end
  end

  class RedisBackend
    def initialize(redis)
      @redis = redis
    end

    def add_ids(ids)
      members = ids.map(&:to_s)
      @redis.sadd(PENDING_KEY, *members) if members.any?
    end

    def drain(limit)
      Array(@redis.spop(PENDING_KEY, limit)).map(&:to_i)
    end

    def pending_ids
      @redis.smembers(PENDING_KEY).map(&:to_i)
    end

    def pending?
      @redis.scard(PENDING_KEY).to_i.positive?
    end

    def claim_flush!(ttl:)
      @redis.set(FLUSH_KEY, "1", nx: true, ex: [ttl.to_i, 1].max)
    end

    def release_flush!
      @redis.del(FLUSH_KEY)
    end

    def reset!
      @redis.del(PENDING_KEY, FLUSH_KEY)
    end
  end
end
