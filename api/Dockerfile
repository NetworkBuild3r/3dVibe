FROM ruby:3.3.6-bookworm

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends libpq-dev libyaml-dev shared-mime-info p7zip-full \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
RUN chmod +x bin/rails bin/rake bin/setup

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
