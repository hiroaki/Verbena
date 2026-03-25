#!/bin/bash
set -e

RAILS_ENV=${RAILS_ENV:-development}
export RAILS_ENV
echo "[docker-entrypoint] RAILS_ENV=$RAILS_ENV"

# Memo:
# Assets are precompiled at image build time in Dockerfile.

# Set up the database schema file according to the selected adapter
echo "[docker-entrypoint] Placing db/schema.rb ..."
case "$DATABASE_ADAPTER" in
  mysql2)
    cp db/schema.mysql2.rb db/schema.rb
    ;;
  postgresql)
    cp db/schema.postgresql.rb db/schema.rb
    ;;
  sqlite3)
    cp db/schema.sqlite3.rb db/schema.rb
    ;;
  *)
    echo "[docker-entrypoint] Unknown DATABASE_ADAPTER: $DATABASE_ADAPTER"
    exit 1
    ;;
esac

if [ "$RAILS_ENV" = "development" ]; then
  echo "[docker-entrypoint] Skipping db:prepare in development. Please run manually if needed."
else
  echo "[docker-entrypoint] Preparing database..."
  bin/rails db:prepare
fi

# Remove a potentially pre-existing server.pid for Rails.
rm -f `dirname $0`/tmp/pids/server.pid

# Then exec the container's main process (what's set as CMD in the Dockerfile).
exec "$@"
