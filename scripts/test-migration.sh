#!/usr/bin/env bash
# Test script for local migration testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🧪 Testing Database Migration Locally"
echo "======================================"
echo ""

# Check for psql
if ! command -v psql >/dev/null 2>&1; then
  echo "❌ PostgreSQL client (psql) is not installed!"
  echo ""
  echo "To install on macOS:"
  echo "  brew install postgresql@15"
  echo ""
  echo "Or download Postgres.app:"
  echo "  https://postgresapp.com/"
  echo ""
  exit 1
fi

echo "✓ PostgreSQL client found: $(psql --version)"
echo ""

# Check if .env.test exists
if [[ ! -f "$PROJECT_ROOT/.env.test" ]]; then
  echo "❌ .env.test file not found!"
  echo ""
  echo "Please create $PROJECT_ROOT/.env.test with your database credentials:"
  echo ""
  echo "  export DB_HOST=\"your-host.db.ondigitalocean.com\""
  echo "  export DB_PORT=\"25060\""
  echo "  export DB_USER=\"doadmin\""
  echo "  export DB_PASSWORD=\"your-password\""
  echo "  export DB_NAME=\"defaultdb\""
  echo "  export SSL_MODE=\"require\""
  echo ""
  exit 1
fi

# Load environment variables
echo "Loading test environment variables..."
source "$PROJECT_ROOT/.env.test"

# Validate required variables
required_vars=("DB_HOST" "DB_PORT" "DB_USER" "DB_PASSWORD" "DB_NAME")
missing_vars=()

for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing_vars+=("$var")
  fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
  echo "❌ Missing required environment variables:"
  for var in "${missing_vars[@]}"; do
    echo "   - $var"
  done
  echo ""
  echo "Please update .env.test with all required values."
  exit 1
fi

echo "✓ All required environment variables set"
echo ""

# Display connection info (hide password)
echo "Connection details:"
echo "  Host: $DB_HOST"
echo "  Port: $DB_PORT"
echo "  User: $DB_USER"
echo "  Database: $DB_NAME"
echo "  Password: ${DB_PASSWORD:0:4}****${DB_PASSWORD: -4}"
echo ""

# Ask for confirmation
read -p "Run migration test? (yes/no): " -r
echo ""
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
  echo "Migration test canceled."
  exit 0
fi

# Run the migration
echo "🚀 Running migration script..."
echo ""

cd "$SCRIPT_DIR"
./migrate-to-do.sh "$@"

echo ""
echo "✅ Test completed successfully!"

