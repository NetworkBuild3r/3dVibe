# Production API / Sidekiq image for 3dvibe
FROM ruby:3.3.6-bookworm AS base

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libpq-dev \
    libyaml-dev \
    shared-mime-info \
    p7zip-full \
    libvips42 \
    libvips-dev \
    curl \
  && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    BUNDLE_PATH=/usr/local/bundle

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3 \
  && rm -rf /usr/local/bundle/cache/*.gem \
  && find /usr/local/bundle -name "*.o" -delete \
  && find /usr/local/bundle -name "*.c" -delete

COPY . .
RUN chmod +x bin/rails bin/rake bin/docker-entrypoint

EXPOSE 3000

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
