require "test_helper"

class ScanSettingsTest < ActiveSupport::TestCase
  KEYS = %w[
    VIBE_SCAN_QUEUE VIBE_SCAN_CONCURRENCY VIBE_SIDEKIQ_CONCURRENCY
  ].freeze

  def teardown
    KEYS.each { |key| ENV.delete(key) }
  end

  test "defaults isolate scan onto its own queue and one thread" do
    assert_equal "scan", ScanSettings.queue
    assert_equal 1, ScanSettings.concurrency
    assert_equal 5, ScanSettings.worker_concurrency
    refute_includes ScanSettings.isolated_queues, "scan"
    assert_includes ScanSettings.isolated_queues, "default"
    assert_includes ScanSettings.isolated_queues, "print"
    assert_includes ScanSettings.isolated_queues, "search"

    layout = ScanSettings.sidekiq_layout
    assert_equal 5, layout[:default][:concurrency]
    assert_equal ScanSettings.isolated_queues, layout[:default][:queues].map(&:first)
    assert_equal 2, layout[:default][:queues].assoc("covers").last
    assert_operator layout[:default][:queues].assoc("default").last, :>, layout[:default][:queues].assoc("covers").last
    assert_equal 1, layout[:scan][:concurrency]
    assert_equal ["scan"], layout[:scan][:queues]
  end

  test "VIBE_SCAN_QUEUE retargets the isolated capsule" do
    ENV["VIBE_SCAN_QUEUE"] = "nfs-walk"
    assert_equal "nfs-walk", ScanSettings.queue
    assert_equal ["nfs-walk"], ScanSettings.sidekiq_layout[:scan][:queues]
    refute_includes ScanSettings.isolated_queues, "nfs-walk"
  end

  test "scan queue cannot steal a critical queue name" do
    %w[default print search previews covers curation duplicates].each do |name|
      ENV["VIBE_SCAN_QUEUE"] = name
      assert_equal "scan", ScanSettings.queue, "expected #{name} to fall back to scan"
    end
  end

  test "blank or dirty queue names fall back to scan" do
    ENV["VIBE_SCAN_QUEUE"] = "  "
    assert_equal "scan", ScanSettings.queue
    ENV["VIBE_SCAN_QUEUE"] = "SCAN!!"
    assert_equal "scan", ScanSettings.queue
    ENV["VIBE_SCAN_QUEUE"] = "Deep_Walk-2"
    assert_equal "deep_walk-2", ScanSettings.queue
  end

  test "concurrency clamps to 1..32" do
    ENV["VIBE_SCAN_CONCURRENCY"] = "0"
    assert_equal 1, ScanSettings.concurrency
    ENV["VIBE_SCAN_CONCURRENCY"] = "-4"
    assert_equal 1, ScanSettings.concurrency
    ENV["VIBE_SCAN_CONCURRENCY"] = "2"
    assert_equal 2, ScanSettings.concurrency
    ENV["VIBE_SCAN_CONCURRENCY"] = "99"
    assert_equal 32, ScanSettings.concurrency

    ENV["VIBE_SIDEKIQ_CONCURRENCY"] = "0"
    assert_equal 5, ScanSettings.worker_concurrency
    ENV["VIBE_SIDEKIQ_CONCURRENCY"] = "8"
    assert_equal 8, ScanSettings.worker_concurrency
  end

  test "as_api exposes queue knobs without changing budget keys" do
    payload = ScanSettings.as_api
    assert_equal "scan", payload[:queue]
    assert_equal 1, payload[:concurrency]
    assert_equal 5, payload[:worker_concurrency]
    assert payload.key?(:max_files)
    assert_equal({ max_seconds: 120, max_files: 5_000, max_folders: 200 }, ScanSettings.budgets_as_api)
  end
end
