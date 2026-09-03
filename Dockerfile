# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.3.8
FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips postgresql-client libpq-dev \
      build-essential git pkg-config && \
    rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test"

# --- build stage ---
FROM base AS build

COPY Gemfile Gemfile.lock ./
COPY vendor/llama_bot_rails vendor/llama_bot_rails/
RUN bundle install && \
    rm -rf ~/.bundle /usr/local/bundle/ruby/*/cache

COPY package.json package-lock.json* ./
RUN npm install 2>/dev/null || true

COPY . .

# Precompile assets (needs dummy secret)
RUN SECRET_KEY_BASE=dummy bundle exec rails assets:precompile

# --- final stage ---
FROM base

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails /rails/db /rails/log /rails/storage /rails/tmp 2>/dev/null || true

USER 1000:1000
EXPOSE 3000
CMD ["./bin/docker-entrypoint"]
