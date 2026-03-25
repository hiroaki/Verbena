#!/bin/sh

# Database initialization script for Verbena environments
#
# This script is designed to be idempotent - it can be run multiple times safely
# without causing side effects. It checks for existing privileges before making changes.
#
# Environment variables required:
#   MYSQL_ROOT_PASSWORD - Root password for MySQL database
#   MYSQL_USER - Username for Rails application database access
#
# Environment variables optional:
#   DATABASE_NAME - Base database name (default: verbena)
#   DATABASE_ENVS - Comma-separated target environments (default: development,test)
#                   Example: staging
#                            production
#                            development,test,staging
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

# Helper function: trim leading/trailing spaces
trim() {
	value="$1"
	# shellcheck disable=SC2001
	echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Helper function: check if user has any privileges for the given database
# Returns 0 (success) if privileges exist, 1 (failure) if they don't
has_privs_for_db() {
	db="$1"
	# Query mysql.db table to check for existing privileges
	count=$(mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sse "SELECT COUNT(*) FROM mysql.db WHERE User='${MYSQL_USER}' AND Db='${db}'")
	[ "${count}" -gt 0 ]
}

DB_BASE=${DATABASE_NAME:-verbena}
TARGET_ENVS=${DATABASE_ENVS:-development,test}

if [ -z "$(trim "${TARGET_ENVS}")" ]; then
	echo "Error: DATABASE_ENVS is empty. Set at least one environment name." >&2
	exit 1
fi

TARGET_DBS=""

old_ifs=$IFS
IFS=','
for raw_env in ${TARGET_ENVS}; do
	env_name=$(trim "${raw_env}")
	if [ -z "${env_name}" ]; then
		continue
	fi

	if ! echo "${env_name}" | grep -Eq '^[A-Za-z0-9_]+$'; then
		echo "Error: DATABASE_ENVS contains invalid environment '${env_name}'. Only alphanumeric and underscore are allowed." >&2
		exit 1
	fi

	TARGET_DBS="${TARGET_DBS} ${DB_BASE}_${env_name}"
done
IFS=$old_ifs

TARGET_DBS=$(trim "${TARGET_DBS}")
if [ -z "${TARGET_DBS}" ]; then
	echo "Error: No target databases resolved from DATABASE_ENVS='${TARGET_ENVS}'" >&2
	exit 1
fi

echo "initdb: ensuring privileges for user ${MYSQL_USER} on: ${TARGET_DBS}"

for db in ${TARGET_DBS}; do
	mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${db}\`;"
done

for db in ${TARGET_DBS}; do
	if has_privs_for_db "${db}"; then
		echo "initdb: privileges for ${MYSQL_USER} on ${db} already present — skipping"
	else
		echo "initdb: granting privileges on ${db} to ${MYSQL_USER}"
		mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${MYSQL_USER}'@'%';"
		SKIP_FLUSH=0
	fi
done

# Only flush privileges if we made changes (optimization)
if [ "${SKIP_FLUSH}" -eq 0 ]; then
	echo "initdb: flushing privileges"
	mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
else
	echo "initdb: no changes made; skipping FLUSH PRIVILEGES"
fi

echo "initdb: database user initialization completed successfully"
exit 0

