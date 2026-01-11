#!/bin/bash
set -e

# This script runs automatically when the container is initialized.
# It creates the test database and ensures the application user exists.

DB_BASE=${DATABASE_NAME:-verbena}
DEV_DB="${DB_BASE}_development"
TEST_DB="${DB_BASE}_test"

echo "initdb: Setup for ${DEV_DB} and ${TEST_DB}"

# POSTGRES_DB (development) is created by the entrypoint env var.
# We create the test database.
echo "initdb: Creating database ${TEST_DB}"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
    CREATE DATABASE "$TEST_DB";
EOSQL

# Handle application user creation if different from superuser
if [ "$APP_USER" != "$POSTGRES_USER" ]; then
    echo "initdb: Creating application user ${APP_USER}"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
        -- Create user with password
        CREATE USER "$APP_USER" WITH PASSWORD '$APP_PASS';
        
        -- Grant ownership of databases to the app user
        -- This allows the app user to create schemas/tables (migrations)
        ALTER DATABASE "$DEV_DB" OWNER TO "$APP_USER";
        ALTER DATABASE "$TEST_DB" OWNER TO "$APP_USER";
EOSQL
    echo "initdb: User ${APP_USER} configured."
else
    echo "initdb: APP_USER is same as POSTGRES_USER, skipping user creation."
fi
