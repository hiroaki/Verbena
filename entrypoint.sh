#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -f `dirname $0`/tmp/pids/server.pid

RAILS_ENV=${RAILS_ENV:-development}
export RAILS_ENV

echo "entrypoint.sh: RAILS_ENV=$RAILS_ENV"
# Assets are precompiled at image build time in Dockerfile.

# Then exec the container's main process (what's set as CMD in the Dockerfile).
exec "$@"
