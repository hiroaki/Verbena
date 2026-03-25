# # For production environment
# $ docker build --build-arg RAILS_ENV=production -t verbena-production:latest .
#
# # For staging environment
# $ docker build --build-arg RAILS_ENV=staging -t verbena-staging:latest .
#
# # For development environment
# $ docker build --build-arg RAILS_ENV=development -t verbena-development:latest .

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.4.9

ARG RAILS_ENV=production

FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim AS base

# Re-declare ARG before using it in ENV
ARG RAILS_ENV

# Rails app lives here
WORKDIR /rails

# Set environment with flexibility for staging/production
ENV BUNDLE_PATH="/usr/local/bundle" \
    RAILS_ENV=$RAILS_ENV

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems and run the application
RUN DEBIAN_FRONTEND=noninteractive apt-get update -qq \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      build-essential \
      pkg-config \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      zlib1g-dev \
      libpq-dev \
      default-libmysqlclient-dev \
      libsqlite3-dev \
      && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && truncate -s 0 /var/log/*log

# Upgrade bundler to match Gemfile.lock BUNDLED WITH version
RUN gem install bundler:4.0.8
RUN gem update --system 4.0.8

# Install application gems
COPY Gemfile Gemfile.lock ./
# NOTE:
# We use `bundle config set --local without 'development test'` and `bundle config set deployment true`
# instead of environment variables, because some tools (e.g. bootsnap precompile) require .bundle/config
# to correctly recognize excluded gem groups. Using only environment variables may cause build failures
# when gems in excluded groups are missing.
RUN if [ "$RAILS_ENV" = "development" ]; then \
      bundle config unset --local without; \
      bundle install; \
    else \
      bundle config set --local without 'development test'; \
      bundle config set deployment true; \
      bundle install; \
    fi && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile -j 0 --gemfile app/ lib/ config/

# Precompiling assets without requiring secret RAILS_MASTER_KEY
# VERBENA_DELIVERY_METHOD and DATABASE_ADAPTER prevents required boot checks during build.
RUN if [ "$RAILS_ENV" != "development" ]; then \
      SECRET_KEY_BASE_DUMMY=1 \
      VERBENA_DELIVERY_METHOD=test \
      DATABASE_ADAPTER=sqlite3 \
      ./bin/rails assets:precompile; \
    else \
      echo "Skip assets:precompile in development"; \
    fi

# Final stage for app image
FROM base

# Install packages needed for deployment
RUN DEBIAN_FRONTEND=noninteractive apt-get update -qq \
  && if [ "$RAILS_ENV" = "development" ]; then \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      build-essential \
      pkg-config \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      zlib1g-dev \
      libpq-dev \
      default-libmysqlclient-dev \
      libsqlite3-dev \
      libsqlite3-0 \
      vim-tiny \
      less \
      curl; \
  else \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      libxml2 \
      libxslt1.1 \
      zlib1g \
      libpq5 \
      libmariadb3 \
      libsqlite3-0 \
      curl; \
  fi \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Upgrade bundler to match Gemfile.lock BUNDLED WITH version
RUN gem install bundler:4.0.8
RUN gem update --system 4.0.8

# Copy built artifacts: application
COPY --from=build /rails /rails
COPY --from=build /usr/local/bundle /usr/local/bundle

# Run and own only the runtime files as a non-root user for security
RUN useradd rails --create-home --shell /bin/bash \
  && mkdir -p /rails/db /rails/log /rails/storage /rails/tmp /usr/local/bundle \
  && chown -R rails:rails /rails /usr/local/bundle \
  && chmod 755 /usr/local/bundle

USER rails:rails

ENTRYPOINT ["/bin/bash", "/rails/entrypoint.sh"]
CMD ["/bin/bash", "-lc", "exec bundle exec rails server -b \"${BINDING:-0.0.0.0}\" -p \"${PORT:-3000}\""]
