#!/usr/bin/env bash
set -euo pipefail

# Migrate database schema and seed data to DigitalOcean PostgreSQL
# Usage: ./migrate-to-do.sh [--schema-only|--seed-only]

if ! command -v psql >/dev/null; then
  echo "psql CLI is required (install PostgreSQL client)." >&2
  exit 1
fi

# Parse arguments
APPLY_SCHEMA=true
APPLY_SEED=true

while [[ $# -gt 0 ]]; do
  case $1 in
    --schema-only)
      APPLY_SEED=false
      shift
      ;;
    --seed-only)
      APPLY_SCHEMA=false
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--schema-only|--seed-only]" >&2
      exit 1
      ;;
  esac
done

# Database connection details (from environment)
: "${DB_HOST:?Set DB_HOST with the DigitalOcean database host}"
: "${DB_PORT:?Set DB_PORT with the DigitalOcean database port}"
: "${DB_USER:?Set DB_USER with the DigitalOcean database user}"
: "${DB_PASSWORD:?Set DB_PASSWORD with the DigitalOcean database password}"
: "${DB_NAME:?Set DB_NAME with the DigitalOcean database name}"

# Optional: SSL mode (default to require for DigitalOcean)
SSL_MODE="${SSL_MODE:-require}"

# Construct connection string
export PGPASSWORD="$DB_PASSWORD"
PSQL_CMD="psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -v ON_ERROR_STOP=1"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="$SCRIPT_DIR/../schemas"

echo ">> Migrating database to DigitalOcean PostgreSQL"
echo "   Host: $DB_HOST:$DB_PORT"
echo "   Database: $DB_NAME"
echo "   User: $DB_USER"

# Test connection
echo ">> Testing connection..."
if ! $PSQL_CMD -c "SELECT version();" >/dev/null; then
  echo "❌ Failed to connect to database" >&2
  exit 1
fi
echo "   ✓ Connected successfully"

# Apply schema
if [[ "$APPLY_SCHEMA" == "true" ]]; then
  echo ">> Applying schema..."
  if [[ ! -f "$SCHEMAS_DIR/schema.sql" ]]; then
    echo "❌ Schema file not found: $SCHEMAS_DIR/schema.sql" >&2
    exit 1
  fi
  
  echo "   Executing schema.sql..."
  if $PSQL_CMD -f "$SCHEMAS_DIR/schema.sql" 2>&1; then
    echo "   ✓ Schema applied successfully"
  else
    EXIT_CODE=$?
    echo "   ❌ Schema application failed with exit code $EXIT_CODE"
    echo "   Check the errors above for details"
    exit 1
  fi
fi

# Apply seed data
if [[ "$APPLY_SEED" == "true" ]]; then
  echo ">> Applying seed data..."
  if [[ ! -f "$SCHEMAS_DIR/seed.sql" ]]; then
    echo "❌ Seed file not found: $SCHEMAS_DIR/seed.sql" >&2
    exit 1
  fi
  
  echo "   Executing seed.sql..."
  if $PSQL_CMD -f "$SCHEMAS_DIR/seed.sql" 2>&1; then
    echo "   ✓ Seed data applied successfully"
  else
    EXIT_CODE=$?
    echo "   ❌ Seed data application failed with exit code $EXIT_CODE"
    echo "   Check the errors above for details"
    exit 1
  fi
fi

# Verify tables
echo ">> Verifying database state..."
TABLES=$($PSQL_CMD -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
TABLES=$(echo "$TABLES" | xargs) # trim whitespace
echo "   Found $TABLES tables in database"

if [[ "$TABLES" -gt 0 ]]; then
  echo "   ✓ Migration completed successfully"
  
  # Show table list
  echo ""
  echo "Tables in database:"
  $PSQL_CMD -c "\dt"
  
  # Show row counts for seed tables
  if [[ "$APPLY_SEED" == "true" ]]; then
    echo ""
    echo "Row counts:"
    $PSQL_CMD -c "SELECT 'muscle_groups' as table_name, COUNT(*) as rows FROM muscle_groups
                  UNION ALL
                  SELECT 'workout_routines', COUNT(*) FROM workout_routines
                  UNION ALL
                  SELECT 'workout_days', COUNT(*) FROM workout_days
                  UNION ALL
                  SELECT 'workout_day_sets', COUNT(*) FROM workout_day_sets;" 2>/dev/null || true
  fi
else
  echo "   ⚠️  No tables found - migration may have failed"
  exit 1
fi

cat <<EOF

Migration complete!

To connect to your database:
  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME

EOF

