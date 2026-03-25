#!/bin/bash

# Database initialization script for Verbena PostgreSQL environments
#
# This script is designed to be idempotent - it can be run multiple times safely
# without causing side effects.
#
# Environment variables required:
#   POSTGRES_USER             - Superuser name for PostgreSQL
#   VERBENA_DATABASE_USER     - Username for Rails application database access
#   VERBENA_DATABASE_PASSWORD - Password for application DB user
#
# Environment variables optional:
#   DATABASE_NAME - Base database name (default: verbena)
#   DATABASE_ENVS - Comma-separated target environments (default: development,test)
#                   Example: staging
#                            production
#                            development,test,staging,production

set -eu  # Exit on error or undefined variables

# Validate required environment variables
: "${POSTGRES_USER?Need POSTGRES_USER env var}"
: "${VERBENA_DATABASE_USER?Need VERBENA_DATABASE_USER env var}"
: "${VERBENA_DATABASE_PASSWORD?Need VERBENA_DATABASE_PASSWORD env var}"

# Validate VERBENA_DATABASE_USER (allow only alphanumeric and underscore)
if ! echo "$VERBENA_DATABASE_USER" | grep -Eq '^[A-Za-z0-9_]+$'; then
    echo "Error: VERBENA_DATABASE_USER contains invalid characters. Only alphanumeric and underscore are allowed." >&2
    exit 1
fi

# Helper function: trim leading/trailing spaces
trim() {
    value="$1"
    # shellcheck disable=SC2001
    echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Helper function: run SQL as PostgreSQL superuser against postgres DB
psql_super() {
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" "$@"
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

echo "initdb: ensuring application role ${VERBENA_DATABASE_USER}"

role_exists=$(psql_super -Atqc "SELECT 1 FROM pg_roles WHERE rolname = '${VERBENA_DATABASE_USER}'")
if [ "${role_exists}" = "1" ]; then
    echo "initdb: role ${VERBENA_DATABASE_USER} already exists - updating password"
    psql_super -v app_user="$VERBENA_DATABASE_USER" -v app_pass="$VERBENA_DATABASE_PASSWORD" <<-'EOSQL'
        SELECT format('ALTER USER %I WITH PASSWORD %L', :'app_user', :'app_pass') \gexec
EOSQL
else
    echo "initdb: creating role ${VERBENA_DATABASE_USER}"
    psql_super -v app_user="$VERBENA_DATABASE_USER" -v app_pass="$VERBENA_DATABASE_PASSWORD" <<-'EOSQL'
        SELECT format('CREATE USER %I WITH PASSWORD %L', :'app_user', :'app_pass') \gexec
EOSQL
fi

echo "initdb: ensuring databases for environments: ${TARGET_DBS}"
for db in ${TARGET_DBS}; do
    db_exists=$(psql_super -Atqc "SELECT 1 FROM pg_database WHERE datname = '${db}'")
    if [ "${db_exists}" = "1" ]; then
        echo "initdb: database ${db} already exists - skipping create"
    else
        echo "initdb: creating database ${db}"
        psql_super -v db_name="$db" <<-'EOSQL'
            SELECT format('CREATE DATABASE %I', :'db_name') \gexec
EOSQL
    fi

    # Ensure ownership for migrations and schema changes.
    psql_super -v db_name="$db" -v app_user="$VERBENA_DATABASE_USER" <<-'EOSQL'
        SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'app_user') \gexec
EOSQL
done

echo "initdb: PostgreSQL initialization completed successfully"
exit 0
