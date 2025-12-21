#!/bin/sh

# Database initialization script for Verbena development environment
#
# This script is designed to be idempotent - it can be run multiple times safely
# without causing side effects. It checks for existing privileges before making changes.
#
# Environment variables required:
#   MYSQL_ROOT_PASSWORD - Root password for MySQL database
#   MYSQL_USER - Username for Rails application database access
#
# Note:
# - MYSQL_PASSWORD is set by MariaDB for MYSQL_USER; this script only grants database privileges
# - This script runs automatically via docker-entrypoint-initdb.d when the
#   MySQL container is first created (when no existing volume data is present)

set -eu  # Exit on error or undefined variables

# Validate required environment variables
: "${MYSQL_ROOT_PASSWORD?Need MYSQL_ROOT_PASSWORD env var}"
: "${MYSQL_USER?Need MYSQL_USER env var}"

# Validate MYSQL_USER (allow only alphanumeric and underscore)
if ! echo "$MYSQL_USER" | grep -Eq '^[A-Za-z0-9_]+$'; then
	echo "Error: MYSQL_USER contains invalid characters. Only alphanumeric and underscore are allowed." >&2
	exit 1
fi

# Flag to track if any changes were made (for FLUSH PRIVILEGES optimization)
SKIP_FLUSH=1

# Helper function: check if user has any privileges for the given database
# Returns 0 (success) if privileges exist, 1 (failure) if they don't
has_privs_for_db() {
	db="$1"
	# Query mysql.db table to check for existing privileges
	# Use '|| echo 0' to handle cases where the query might fail
	count=$(mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sse "SELECT COUNT(*) FROM mysql.db WHERE User='${MYSQL_USER}' AND Db='${db}'" || echo 0)
	[ "${count}" -gt 0 ]
}

echo "initdb: ensuring privileges for user ${MYSQL_USER}"

# Check and grant privileges for development database
if has_privs_for_db "verbena_development"; then
	echo "initdb: privileges for ${MYSQL_USER} on verbena_development already present — skipping"
else
	echo "initdb: granting privileges on verbena_development to ${MYSQL_USER}"
	mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON verbena_development.* TO '${MYSQL_USER}'@'%';"
	SKIP_FLUSH=0
fi

# Check and grant privileges for test database
if has_privs_for_db "verbena_test"; then
	echo "initdb: privileges for ${MYSQL_USER} on verbena_test already present — skipping"
else
	echo "initdb: granting privileges on verbena_test to ${MYSQL_USER}"
	mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON verbena_test.* TO '${MYSQL_USER}'@'%';"
	SKIP_FLUSH=0
fi

# Only flush privileges if we made changes (optimization)
if [ "${SKIP_FLUSH}" -eq 0 ]; then
	echo "initdb: flushing privileges"
	mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
else
	echo "initdb: no changes made; skipping FLUSH PRIVILEGES"
fi

echo "initdb: database user initialization completed successfully"
exit 0

