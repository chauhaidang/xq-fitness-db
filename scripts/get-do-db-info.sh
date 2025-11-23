#!/usr/bin/env bash
# Fetch DigitalOcean database connection details using API

set -euo pipefail

if [[ -z "${DO_TOKEN:-}" ]]; then
  echo "❌ DO_TOKEN environment variable not set"
  echo "   Set it with: export DO_TOKEN=your-token"
  exit 1
fi

echo "🔍 Fetching DigitalOcean databases..."
echo ""

# List all databases
DATABASES=$(curl -s -X GET \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DO_TOKEN" \
  "https://api.digitalocean.com/v2/databases")

# Check if request was successful
if ! echo "$DATABASES" | jq -e '.databases' >/dev/null 2>&1; then
  echo "❌ Failed to fetch databases"
  echo "$DATABASES"
  exit 1
fi

# Parse and display databases
DB_COUNT=$(echo "$DATABASES" | jq '.databases | length')

if [[ "$DB_COUNT" -eq 0 ]]; then
  echo "No databases found in your DigitalOcean account."
  exit 0
fi

echo "Found $DB_COUNT database(s):"
echo ""

# Display each database
echo "$DATABASES" | jq -r '.databases[] | 
  "Name: \(.name)\n" +
  "ID: \(.id)\n" +
  "Engine: \(.engine) \(.version)\n" +
  "Status: \(.status)\n" +
  "Host: \(.connection.host)\n" +
  "Port: \(.connection.port)\n" +
  "User: \(.connection.user)\n" +
  "Database: \(.connection.database)\n" +
  "SSL Required: \(.connection.ssl)\n" +
  "──────────────────────────────────────\n"'

# Offer to export connection details for the first database
FIRST_DB=$(echo "$DATABASES" | jq -r '.databases[0]')
DB_NAME=$(echo "$FIRST_DB" | jq -r '.name')

echo ""
read -p "Export connection details for '$DB_NAME'? (yes/no): " -r
echo ""

if [[ $REPLY =~ ^[Yy]es$ ]]; then
  DB_HOST=$(echo "$FIRST_DB" | jq -r '.connection.host')
  DB_PORT=$(echo "$FIRST_DB" | jq -r '.connection.port')
  DB_USER=$(echo "$FIRST_DB" | jq -r '.connection.user')
  DB_DATABASE=$(echo "$FIRST_DB" | jq -r '.connection.database')
  
  echo "Add these to your shell:"
  echo ""
  echo "export DB_HOST=\"$DB_HOST\""
  echo "export DB_PORT=\"$DB_PORT\""
  echo "export DB_USER=\"$DB_USER\""
  echo "export DB_PASSWORD=\"\${DO_XQ_FITNESS_DB_PASS}\""
  echo "export DB_NAME=\"$DB_DATABASE\""
  echo "export SSL_MODE=\"require\""
  echo ""
  echo "Copy the above and run in your terminal, then:"
  echo "  cd database/scripts"
  echo "  ./test-migration.sh"
fi

