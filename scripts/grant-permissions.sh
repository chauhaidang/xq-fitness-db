#!/usr/bin/env bash
set -euo pipefail

# Script to grant database permissions to the app user
# This fixes the "permission denied for table" errors

if ! command -v doctl >/dev/null; then
  echo "doctl CLI is required (https://docs.digitalocean.com/reference/doctl/)." >&2
  exit 1
fi

if ! command -v jq >/dev/null; then
  echo "jq is required for parsing DigitalOcean JSON responses." >&2
  exit 1
fi

if ! command -v psql >/dev/null; then
  echo "psql is required for executing SQL commands." >&2
  echo "Install PostgreSQL client tools to use this script." >&2
  exit 1
fi

: "${DO_TOKEN:?Set DO_TOKEN with a DigitalOcean API token that has write access.}"

REGION="${REGION:-sgp1}"
APP_NAME="${APP_NAME:-xq-fitness}"
DB_CLUSTER_NAME="${DB_CLUSTER_NAME:-${APP_NAME}-db}"
APP_DB_NAME="${APP_DB_NAME:-xq_fitness}"
APP_DB_USER="${APP_DB_USER:-xq_app_user}"

echo ">> Authenticating doctl context"
doctl auth init -t "$DO_TOKEN" >/dev/null

# Use DB_CLUSTER_ID if provided, otherwise look up by name
if [[ -n "${DB_CLUSTER_ID:-}" ]]; then
  echo ">> Using provided database cluster ID: $DB_CLUSTER_ID"
else
  echo ">> Finding database cluster ($DB_CLUSTER_NAME)"
  DB_CLUSTER_ID=$(doctl databases list --output json | jq -r '.[] | select(.name=="'"$DB_CLUSTER_NAME"'") | .id' || echo "")
  
  if [[ -z "$DB_CLUSTER_ID" ]]; then
    echo "❌ Error: Database cluster '$DB_CLUSTER_NAME' not found" >&2
    exit 1
  fi
  
  echo "   Found cluster: $DB_CLUSTER_ID"
fi

echo ">> Fetching connection details"
CONNECTION_JSON=$(doctl databases connection "$DB_CLUSTER_ID" --output json)

# Handle both array and object formats
if echo "$CONNECTION_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  DB_HOST=$(echo "$CONNECTION_JSON" | jq -r '.[0].host // .[0].uri // empty')
  DB_PORT=$(echo "$CONNECTION_JSON" | jq -r '.[0].port // empty')
else
  DB_HOST=$(echo "$CONNECTION_JSON" | jq -r '.host // .uri // empty')
  DB_PORT=$(echo "$CONNECTION_JSON" | jq -r '.port // empty')
fi

# If host is a URI, extract hostname from it
if [[ "$DB_HOST" == *"@"* ]]; then
  DB_HOST=$(echo "$DB_HOST" | sed -E 's/.*@([^:]+).*/\1/')
fi

if [[ -z "$DB_HOST" ]] || [[ -z "$DB_PORT" ]]; then
  echo "❌ Error: Failed to extract database connection details" >&2
  exit 1
fi

echo "   Host: $DB_HOST"
echo "   Port: $DB_PORT"
echo "   Database: $APP_DB_NAME"
echo "   User to grant permissions: $APP_DB_USER"

# Get the default postgres user credentials
# DigitalOcean managed databases have a default user with admin privileges
echo ""
echo ">> Getting default database user credentials"
DEFAULT_USER=$(doctl databases user list "$DB_CLUSTER_ID" --output json | jq -r '.[] | select(.name=="doadmin") | .name' | head -1)

if [[ -z "$DEFAULT_USER" ]]; then
  echo "❌ Error: Could not find default database user (doadmin)" >&2
  echo "   You may need to use a different user with admin privileges" >&2
  exit 1
fi

echo "   Using admin user: $DEFAULT_USER"
echo ""
echo "⚠️  You will be prompted for the database password for user '$DEFAULT_USER'"
echo "   You can find this in the DigitalOcean dashboard or reset it if needed"
echo ""

# Get the SQL file path (script directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/grant-permissions.sql"

if [[ ! -f "$SQL_FILE" ]]; then
  echo "❌ Error: SQL file not found: $SQL_FILE" >&2
  exit 1
fi

echo ">> Granting permissions to $APP_DB_USER"
echo "   This will grant SELECT, INSERT, UPDATE, DELETE on all tables"
echo "   and USAGE on all sequences"
echo ""

# Execute SQL using psql
PGPASSWORD="${DB_PASSWORD:-}" psql \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DEFAULT_USER" \
  -d "$APP_DB_NAME" \
  -f "$SQL_FILE" \
  2>&1 || {
  echo ""
  echo "❌ Error: Failed to grant permissions" >&2
  echo ""
  echo "Troubleshooting:" >&2
  echo "1. Make sure you have the password for user '$DEFAULT_USER'" >&2
  echo "2. You can set it via: export DB_PASSWORD='your-password'" >&2
  echo "3. Or you can reset it in the DigitalOcean dashboard" >&2
  echo "4. Make sure your IP is allowed in the database firewall rules" >&2
  exit 1
}

echo ""
echo "✅ Successfully granted permissions to $APP_DB_USER"
echo ""
echo "The write service should now be able to:"
echo "  - INSERT into workout_routines, workout_days, workout_day_sets"
echo "  - UPDATE existing records"
echo "  - DELETE records"
echo "  - SELECT data"
echo "  - Use sequences for auto-incrementing IDs"

