#!/usr/bin/env bash
set -euo pipefail

#######################################################################
# XQ Fitness Database Migration: DigitalOcean → Neon
# 
# This script handles the complete migration from DO Managed PostgreSQL
# to Neon Serverless PostgreSQL.
#
# INITIAL MIGRATION (from DigitalOcean):
#   ./migrate-to-neon.sh export          # Export from DO (pg_dump)
#   ./migrate-to-neon.sh import          # Import to Neon (pg_restore)
#   ./migrate-to-neon.sh validate        # Validate migration
#   ./migrate-to-neon.sh full            # Full migration (export + import + validate)
#
# FUTURE MIGRATIONS (apply new migration scripts to Neon):
#   ./migrate-to-neon.sh schema          # Apply schema.sql only
#   ./migrate-to-neon.sh seed            # Apply seed.sql only
#   ./migrate-to-neon.sh migration <file> # Apply specific migration file
#   ./migrate-to-neon.sh all-migrations  # Apply all migrations in order
#
# Required Environment Variables:
#   For export: DO_DB_HOST, DO_DB_PORT, DO_DB_USER, DO_DB_PASSWORD, DO_DB_NAME
#              Or: DO_DATABASE_URL
#   For import/migrations: NEON_DB_HOST, NEON_DB_PORT, NEON_DB_USER, NEON_DB_PASSWORD, NEON_DB_NAME
#              Or: NEON_DATABASE_URL
#######################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/../backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

#######################################################################
# Helper Functions
#######################################################################

log_info() {
    echo -e "${BLUE}>> $1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v psql >/dev/null; then
        log_error "psql is required. Install PostgreSQL client."
        exit 1
    fi
    
    if ! command -v pg_dump >/dev/null; then
        log_error "pg_dump is required. Install PostgreSQL client."
        exit 1
    fi
    
    log_success "Prerequisites checked"
}

load_do_credentials() {
    if [[ -n "${DO_DATABASE_URL:-}" ]]; then
        log_info "Using DO_DATABASE_URL connection string"
        export DO_CONN="$DO_DATABASE_URL"
    else
        : "${DO_DB_HOST:?Set DO_DB_HOST}"
        : "${DO_DB_PORT:?Set DO_DB_PORT}"
        : "${DO_DB_USER:?Set DO_DB_USER}"
        : "${DO_DB_PASSWORD:?Set DO_DB_PASSWORD}"
        : "${DO_DB_NAME:?Set DO_DB_NAME}"
        export DO_CONN="postgresql://${DO_DB_USER}:${DO_DB_PASSWORD}@${DO_DB_HOST}:${DO_DB_PORT}/${DO_DB_NAME}?sslmode=require"
    fi
}

load_neon_credentials() {
    if [[ -n "${NEON_DATABASE_URL:-}" ]]; then
        log_info "Using NEON_DATABASE_URL connection string"
        export NEON_CONN="$NEON_DATABASE_URL"
    else
        : "${NEON_DB_HOST:?Set NEON_DB_HOST}"
        : "${NEON_DB_PORT:=5432}"
        : "${NEON_DB_USER:?Set NEON_DB_USER}"
        : "${NEON_DB_PASSWORD:?Set NEON_DB_PASSWORD}"
        : "${NEON_DB_NAME:?Set NEON_DB_NAME}"
        export NEON_CONN="postgresql://${NEON_DB_USER}:${NEON_DB_PASSWORD}@${NEON_DB_HOST}:${NEON_DB_PORT}/${NEON_DB_NAME}?sslmode=require"
    fi
}

#######################################################################
# Export from DigitalOcean
#######################################################################

do_export() {
    log_info "Starting export from DigitalOcean..."
    
    load_do_credentials
    mkdir -p "$BACKUP_DIR"
    
    # Test connection
    log_info "Testing DigitalOcean connection..."
    if ! psql "$DO_CONN" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Failed to connect to DigitalOcean database"
        exit 1
    fi
    log_success "Connected to DigitalOcean"
    
    # Get database size
    log_info "Checking database size..."
    DB_SIZE=$(psql "$DO_CONN" -t -c "SELECT pg_size_pretty(pg_database_size(current_database()));")
    echo "   Database size: $DB_SIZE"
    
    # Save row counts for validation
    log_info "Saving row counts for validation..."
    psql "$DO_CONN" -t -c "
        SELECT 'muscle_groups' as table_name, COUNT(*) as row_count FROM muscle_groups
        UNION ALL SELECT 'workout_routines', COUNT(*) FROM workout_routines
        UNION ALL SELECT 'workout_days', COUNT(*) FROM workout_days
        UNION ALL SELECT 'workout_day_sets', COUNT(*) FROM workout_day_sets
        UNION ALL SELECT 'exercises', COUNT(*) FROM exercises
        UNION ALL SELECT 'weekly_snapshots', COUNT(*) FROM weekly_snapshots
        UNION ALL SELECT 'snapshot_workout_days', COUNT(*) FROM snapshot_workout_days
        UNION ALL SELECT 'snapshot_workout_day_sets', COUNT(*) FROM snapshot_workout_day_sets
        UNION ALL SELECT 'snapshot_exercises', COUNT(*) FROM snapshot_exercises
        ORDER BY table_name;
    " > "$BACKUP_DIR/do_row_counts_${TIMESTAMP}.txt" 2>/dev/null || true
    
    # Export full database
    log_info "Exporting full database..."
    BACKUP_FILE="$BACKUP_DIR/xq_fitness_full_${TIMESTAMP}.sql"
    
    pg_dump "$DO_CONN" \
        --no-owner \
        --no-privileges \
        --clean \
        --if-exists \
        -F p \
        -f "$BACKUP_FILE"
    
    BACKUP_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
    log_success "Backup created: $BACKUP_FILE ($BACKUP_SIZE)"
    
    # Export schema only (for reference)
    log_info "Exporting schema only..."
    pg_dump "$DO_CONN" \
        --schema-only \
        --no-owner \
        --no-privileges \
        -F p \
        -f "$BACKUP_DIR/xq_fitness_schema_${TIMESTAMP}.sql"
    log_success "Schema backup created"
    
    echo ""
    log_success "Export completed!"
    echo "   Backup file: $BACKUP_FILE"
    echo "   Row counts: $BACKUP_DIR/do_row_counts_${TIMESTAMP}.txt"
}

#######################################################################
# Import to Neon
#######################################################################

do_import() {
    log_info "Starting import to Neon..."
    
    load_neon_credentials
    
    # Find latest backup file
    if [[ -n "${BACKUP_FILE:-}" ]]; then
        log_info "Using specified backup file: $BACKUP_FILE"
    else
        BACKUP_FILE=$(ls -t "$BACKUP_DIR"/xq_fitness_full_*.sql 2>/dev/null | head -1)
        if [[ -z "$BACKUP_FILE" ]]; then
            log_error "No backup file found. Run 'export' first."
            exit 1
        fi
        log_info "Using latest backup: $BACKUP_FILE"
    fi
    
    # Test Neon connection
    log_info "Testing Neon connection..."
    if ! psql "$NEON_CONN" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Failed to connect to Neon database"
        log_warning "Note: First connection may take a few seconds if compute is suspended"
        exit 1
    fi
    log_success "Connected to Neon"
    
    # Import backup
    log_info "Importing database (this may take a moment)..."
    if psql "$NEON_CONN" -v ON_ERROR_STOP=1 -f "$BACKUP_FILE" 2>&1 | grep -v "^NOTICE:" | grep -v "^DROP" | head -20; then
        log_success "Database imported successfully"
    else
        log_error "Import failed"
        exit 1
    fi
    
    # Reset sequences (in case of any issues)
    log_info "Resetting sequences..."
    psql "$NEON_CONN" -c "
        SELECT setval('muscle_groups_id_seq', COALESCE((SELECT MAX(id) FROM muscle_groups), 0) + 1, false);
        SELECT setval('workout_routines_id_seq', COALESCE((SELECT MAX(id) FROM workout_routines), 0) + 1, false);
        SELECT setval('workout_days_id_seq', COALESCE((SELECT MAX(id) FROM workout_days), 0) + 1, false);
        SELECT setval('workout_day_sets_id_seq', COALESCE((SELECT MAX(id) FROM workout_day_sets), 0) + 1, false);
        SELECT setval('exercises_id_seq', COALESCE((SELECT MAX(id) FROM exercises), 0) + 1, false);
        SELECT setval('weekly_snapshots_id_seq', COALESCE((SELECT MAX(id) FROM weekly_snapshots), 0) + 1, false);
    " >/dev/null 2>&1 || true
    
    log_success "Import completed!"
}

#######################################################################
# Validate Migration
#######################################################################

do_validate() {
    log_info "Validating migration..."
    
    load_neon_credentials
    
    # Find latest DO row counts (may not exist if export wasn't run)
    DO_COUNTS_FILE=""
    if ls "$BACKUP_DIR"/do_row_counts_*.txt >/dev/null 2>&1; then
        DO_COUNTS_FILE=$(ls -t "$BACKUP_DIR"/do_row_counts_*.txt 2>/dev/null | head -1)
    fi
    
    # Test Neon connection
    log_info "Testing Neon connection..."
    if ! psql "$NEON_CONN" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Failed to connect to Neon database"
        exit 1
    fi
    log_success "Connected to Neon"
    
    # Check tables exist
    log_info "Checking tables..."
    TABLES=$(psql "$NEON_CONN" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
    TABLES=$(echo "$TABLES" | xargs)
    echo "   Found $TABLES tables"
    
    if [[ "$TABLES" -lt 5 ]]; then
        log_error "Expected at least 5 tables, found $TABLES"
        exit 1
    fi
    
    # Get Neon row counts
    log_info "Getting Neon row counts..."
    NEON_COUNTS_FILE="$BACKUP_DIR/neon_row_counts_${TIMESTAMP}.txt"
    psql "$NEON_CONN" -t -c "
        SELECT 'muscle_groups' as table_name, COUNT(*) as row_count FROM muscle_groups
        UNION ALL SELECT 'workout_routines', COUNT(*) FROM workout_routines
        UNION ALL SELECT 'workout_days', COUNT(*) FROM workout_days
        UNION ALL SELECT 'workout_day_sets', COUNT(*) FROM workout_day_sets
        UNION ALL SELECT 'exercises', COUNT(*) FROM exercises
        UNION ALL SELECT 'weekly_snapshots', COUNT(*) FROM weekly_snapshots
        UNION ALL SELECT 'snapshot_workout_days', COUNT(*) FROM snapshot_workout_days
        UNION ALL SELECT 'snapshot_workout_day_sets', COUNT(*) FROM snapshot_workout_day_sets
        UNION ALL SELECT 'snapshot_exercises', COUNT(*) FROM snapshot_exercises
        ORDER BY table_name;
    " > "$NEON_COUNTS_FILE" 2>/dev/null || true
    
    # Compare row counts
    log_info "Comparing row counts..."
    echo ""
    echo "=== Neon Row Counts ==="
    cat "$NEON_COUNTS_FILE"
    
    if [[ -n "${DO_COUNTS_FILE:-}" && -f "$DO_COUNTS_FILE" ]]; then
        echo ""
        echo "=== DigitalOcean Row Counts (from export) ==="
        cat "$DO_COUNTS_FILE"
        
        if diff -q "$DO_COUNTS_FILE" "$NEON_COUNTS_FILE" >/dev/null 2>&1; then
            echo ""
            log_success "Row counts match!"
        else
            echo ""
            log_warning "Row counts differ (may be expected if data changed since export)"
            diff "$DO_COUNTS_FILE" "$NEON_COUNTS_FILE" || true
        fi
    fi
    
    # Test sample queries
    log_info "Testing sample queries..."
    
    echo ""
    echo "=== Sample Muscle Groups ==="
    psql "$NEON_CONN" -c "SELECT id, name FROM muscle_groups LIMIT 5;"
    
    echo ""
    echo "=== Sample Routines ==="
    psql "$NEON_CONN" -c "SELECT id, name, is_active FROM workout_routines LIMIT 5;"
    
    echo ""
    log_success "Validation completed!"
    echo ""
    echo "Next steps:"
    echo "  1. Update service environment variables to use Neon"
    echo "  2. Restart services"
    echo "  3. Test API endpoints"
    echo ""
    echo "Neon connection details:"
    echo "  Host: ${NEON_DB_HOST:-'(from NEON_DATABASE_URL)'}"
    echo "  Database: ${NEON_DB_NAME:-'(from NEON_DATABASE_URL)'}"
}

#######################################################################
# Full Migration
#######################################################################

do_full() {
    log_info "Starting full migration: DigitalOcean → Neon"
    echo ""
    
    # Export
    do_export
    echo ""
    
    # Import
    do_import
    echo ""
    
    # Validate
    do_validate
    echo ""
    
    log_success "Full migration completed successfully!"
}

#######################################################################
# Schema and Seed (for fresh setup or updates)
#######################################################################

do_schema() {
    log_info "Applying schema.sql to Neon..."
    
    load_neon_credentials
    
    SCHEMA_FILE="$SCRIPT_DIR/../schemas/schema.sql"
    if [[ ! -f "$SCHEMA_FILE" ]]; then
        log_error "Schema file not found: $SCHEMA_FILE"
        exit 1
    fi
    
    # Test connection
    log_info "Testing Neon connection..."
    if ! psql "$NEON_CONN" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Failed to connect to Neon database"
        exit 1
    fi
    log_success "Connected to Neon"
    
    # Apply schema
    log_info "Executing schema.sql..."
    if psql "$NEON_CONN" -v ON_ERROR_STOP=1 -f "$SCHEMA_FILE" 2>&1 | grep -v "^NOTICE:" | head -20; then
        log_success "Schema applied successfully"
    else
        log_error "Schema application failed"
        exit 1
    fi
}

do_seed() {
    log_info "Applying seed.sql to Neon..."
    
    load_neon_credentials
    
    SEED_FILE="$SCRIPT_DIR/../schemas/seed.sql"
    if [[ ! -f "$SEED_FILE" ]]; then
        log_error "Seed file not found: $SEED_FILE"
        exit 1
    fi
    
    # Test connection
    log_info "Testing Neon connection..."
    if ! psql "$NEON_CONN" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Failed to connect to Neon database"
        exit 1
    fi
    log_success "Connected to Neon"
    
    # Apply seed
    log_info "Executing seed.sql..."
    if psql "$NEON_CONN" -v ON_ERROR_STOP=1 -f "$SEED_FILE" 2>&1 | grep -v "^NOTICE:" | head -20; then
        log_success "Seed data applied successfully"
    else
        log_error "Seed data application failed"
        exit 1
    fi
}

#######################################################################
# Migrations (for incremental updates)
#######################################################################

do_migration() {
    local MIGRATION_FILE="$1"
    
    if [[ -z "$MIGRATION_FILE" ]]; then
        log_error "Migration file name is required"
        echo "Usage: $0 migration <filename>"
        echo "Example: $0 migration 001_add_weekly_snapshots.sql"
        exit 1
    fi
    
    log_info "Applying migration: $MIGRATION_FILE"
    
    load_neon_credentials
    
    MIGRATIONS_DIR="$SCRIPT_DIR/../migrations"
    MIGRATION_PATH="$MIGRATIONS_DIR/$MIGRATION_FILE"
    
    if [[ ! -f "$MIGRATION_PATH" ]]; then
        log_error "Migration file not found: $MIGRATION_PATH"
        echo ""
        echo "Available migrations:"
        ls -1 "$MIGRATIONS_DIR"/*.sql 2>/dev/null | xargs -n1 basename || echo "  (none found)"
        exit 1
    fi
    
    # Test connection
    log_info "Testing Neon connection..."
    if ! psql "$NEON_CONN" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Failed to connect to Neon database"
        exit 1
    fi
    log_success "Connected to Neon"
    
    # Apply migration
    log_info "Executing $MIGRATION_FILE..."
    if psql "$NEON_CONN" -v ON_ERROR_STOP=1 -f "$MIGRATION_PATH" 2>&1; then
        log_success "Migration applied successfully: $MIGRATION_FILE"
    else
        log_error "Migration failed: $MIGRATION_FILE"
        exit 1
    fi
}

do_all_migrations() {
    log_info "Applying all migrations to Neon..."
    
    load_neon_credentials
    
    MIGRATIONS_DIR="$SCRIPT_DIR/../migrations"
    
    if [[ ! -d "$MIGRATIONS_DIR" ]]; then
        log_error "Migrations directory not found: $MIGRATIONS_DIR"
        exit 1
    fi
    
    # Find all .sql files and sort them
    MIGRATION_FILES=$(find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" -type f | sort -V)
    
    if [[ -z "$MIGRATION_FILES" ]]; then
        log_warning "No migration files found in $MIGRATIONS_DIR"
        return 0
    fi
    
    # Test connection
    log_info "Testing Neon connection..."
    if ! psql "$NEON_CONN" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Failed to connect to Neon database"
        exit 1
    fi
    log_success "Connected to Neon"
    
    # Count migrations
    TOTAL=$(echo "$MIGRATION_FILES" | wc -l | xargs)
    log_info "Found $TOTAL migration(s) to apply"
    echo ""
    
    # Apply each migration
    COUNT=0
    while IFS= read -r MIGRATION_PATH; do
        MIGRATION_FILE=$(basename "$MIGRATION_PATH")
        COUNT=$((COUNT + 1))
        
        log_info "[$COUNT/$TOTAL] Applying: $MIGRATION_FILE"
        if psql "$NEON_CONN" -v ON_ERROR_STOP=1 -f "$MIGRATION_PATH" 2>&1 | grep -v "^NOTICE:" | head -5; then
            log_success "Applied: $MIGRATION_FILE"
        else
            log_error "Failed: $MIGRATION_FILE"
            exit 1
        fi
        echo ""
    done <<< "$MIGRATION_FILES"
    
    log_success "All $COUNT migration(s) applied successfully!"
}

#######################################################################
# Fresh Setup (schema + seed + all migrations)
#######################################################################

do_fresh_setup() {
    log_info "Setting up fresh Neon database (schema + seed + all migrations)..."
    echo ""
    
    # Apply schema
    do_schema
    echo ""
    
    # Apply seed data
    do_seed
    echo ""
    
    # Apply all migrations
    do_all_migrations
    echo ""
    
    # Validate
    do_validate
    echo ""
    
    log_success "Fresh setup completed successfully!"
}

#######################################################################
# User Management (create app user and grant permissions)
#######################################################################

do_create_user() {
    log_info "Creating application user in Neon..."
    
    load_neon_credentials
    
    # Support both variable naming conventions
    # DB_USER_AD/DB_PASSWORD_AD (user's convention) or APP_DB_USER/APP_DB_PASSWORD
    local USER_PASSWORD="${DB_PASSWORD_AD:-${APP_DB_PASSWORD:-}}"
    local USER_NAME="${DB_USER_AD:-${APP_DB_USER:-xq_app_user}}"
    
    # Check if password is set
    if [[ -z "$USER_PASSWORD" ]]; then
        log_error "DB_PASSWORD_AD (or APP_DB_PASSWORD) is required to create the app user"
        echo ""
        echo "Usage:"
        echo "  export DB_PASSWORD_AD='your-secure-password'"
        echo "  ./migrate-to-neon.sh create-user"
        exit 1
    fi
    
    APP_DB_USER="$USER_NAME"
    APP_DB_PASSWORD="$USER_PASSWORD"
    
    # Test connection
    log_info "Testing Neon connection..."
    if ! psql "$NEON_CONN" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Failed to connect to Neon database"
        exit 1
    fi
    log_success "Connected to Neon"
    
    # Check if user already exists
    USER_EXISTS=$(psql "$NEON_CONN" -t -c "SELECT 1 FROM pg_roles WHERE rolname = '$APP_DB_USER';" | xargs)
    
    if [[ "$USER_EXISTS" == "1" ]]; then
        log_warning "User '$APP_DB_USER' already exists"
        
        # Update password
        log_info "Updating password for $APP_DB_USER..."
        psql "$NEON_CONN" -c "ALTER USER $APP_DB_USER WITH PASSWORD '$APP_DB_PASSWORD';" >/dev/null
        log_success "Password updated"
    else
        # Create user
        log_info "Creating user: $APP_DB_USER"
        psql "$NEON_CONN" -c "CREATE USER $APP_DB_USER WITH PASSWORD '$APP_DB_PASSWORD';" >/dev/null
        log_success "User created: $APP_DB_USER"
    fi
    
    # Get database name from connection string
    DB_NAME=$(psql "$NEON_CONN" -t -c "SELECT current_database();" | xargs)
    
    # Grant connect privilege
    log_info "Granting CONNECT privilege on database $DB_NAME..."
    psql "$NEON_CONN" -c "GRANT CONNECT ON DATABASE $DB_NAME TO $APP_DB_USER;" >/dev/null 2>&1 || true
    
    echo ""
    log_success "User setup completed!"
    echo ""
    echo "User details:"
    psql "$NEON_CONN" -c "
        SELECT 
            rolname as username,
            rolcanlogin as can_login,
            rolcreatedb as can_create_db,
            rolsuper as is_superuser
        FROM pg_roles 
        WHERE rolname = '$APP_DB_USER';
    "
}

do_grant_permissions() {
    log_info "Granting permissions to application user..."
    
    load_neon_credentials
    
    # Support both variable naming conventions
    APP_DB_USER="${DB_USER_AD:-${APP_DB_USER:-xq_app_user}}"
    
    # Test connection
    log_info "Testing Neon connection..."
    if ! psql "$NEON_CONN" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Failed to connect to Neon database"
        exit 1
    fi
    log_success "Connected to Neon"
    
    # Check if user exists
    USER_EXISTS=$(psql "$NEON_CONN" -t -c "SELECT 1 FROM pg_roles WHERE rolname = '$APP_DB_USER';" | xargs)
    
    if [[ "$USER_EXISTS" != "1" ]]; then
        log_error "User '$APP_DB_USER' does not exist"
        echo "Run './migrate-to-neon.sh create-user' first"
        exit 1
    fi
    
    # Grant permissions
    log_info "Granting schema usage..."
    psql "$NEON_CONN" -c "GRANT USAGE ON SCHEMA public TO $APP_DB_USER;" >/dev/null
    
    log_info "Granting table permissions (SELECT, INSERT, UPDATE, DELETE)..."
    psql "$NEON_CONN" -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $APP_DB_USER;" >/dev/null
    
    log_info "Granting sequence permissions..."
    psql "$NEON_CONN" -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO $APP_DB_USER;" >/dev/null
    
    log_info "Granting function execute permissions..."
    psql "$NEON_CONN" -c "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO $APP_DB_USER;" >/dev/null
    
    log_info "Setting default privileges for future objects..."
    psql "$NEON_CONN" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO $APP_DB_USER;" >/dev/null
    psql "$NEON_CONN" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO $APP_DB_USER;" >/dev/null
    psql "$NEON_CONN" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO $APP_DB_USER;" >/dev/null
    
    echo ""
    log_success "Permissions granted successfully!"
    echo ""
    echo "Verifying permissions:"
    psql "$NEON_CONN" -c "
        SELECT 
            tablename as table_name,
            has_table_privilege('$APP_DB_USER', schemaname||'.'||tablename, 'SELECT') as \"select\",
            has_table_privilege('$APP_DB_USER', schemaname||'.'||tablename, 'INSERT') as \"insert\",
            has_table_privilege('$APP_DB_USER', schemaname||'.'||tablename, 'UPDATE') as \"update\",
            has_table_privilege('$APP_DB_USER', schemaname||'.'||tablename, 'DELETE') as \"delete\"
        FROM pg_tables 
        WHERE schemaname = 'public'
        ORDER BY tablename;
    "
}

do_setup_app_user() {
    log_info "Setting up application user (create + grant permissions)..."
    echo ""
    
    do_create_user
    echo ""
    
    do_grant_permissions
    echo ""
    
    log_success "Application user setup completed!"
    echo ""
    echo "Connection details for app user:"
    echo "  User: ${DB_USER_AD:-${APP_DB_USER:-xq_app_user}}"
    echo "  Host: ${NEON_DB_HOST:-'(from NEON_DATABASE_URL)'}"
    echo "  Database: ${NEON_DB_NAME:-'(from NEON_DATABASE_URL)'}"
}

#######################################################################
# Main
#######################################################################

print_usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "INITIAL MIGRATION (from DigitalOcean):"
    echo "  export          - Export database from DigitalOcean (pg_dump)"
    echo "  import          - Import database to Neon (from backup file)"
    echo "  validate        - Validate migration (compare row counts)"
    echo "  full            - Full migration (export + import + validate)"
    echo ""
    echo "FRESH SETUP (new Neon database from scripts):"
    echo "  fresh-setup     - Apply schema + seed + all migrations"
    echo "  schema          - Apply schema.sql only"
    echo "  seed            - Apply seed.sql only"
    echo ""
    echo "INCREMENTAL MIGRATIONS (apply new scripts to Neon):"
    echo "  migration <file> - Apply specific migration file"
    echo "  all-migrations   - Apply all migrations in order"
    echo ""
    echo "USER MANAGEMENT:"
    echo "  create-user       - Create app user (requires APP_DB_PASSWORD)"
    echo "  grant-permissions - Grant permissions to app user"
    echo "  setup-app-user    - Create user + grant permissions"
    echo ""
    echo "Required Environment Variables:"
    echo "  For export: DO_DATABASE_URL or DO_DB_HOST/PORT/USER/PASSWORD/NAME"
    echo "  For Neon:   NEON_DATABASE_URL or NEON_DB_HOST/PORT/USER/PASSWORD/NAME"
    echo ""
    echo "Optional Environment Variables (for user management):"
    echo "  DB_USER_AD      - App user name (default: xq_app_user)"
    echo "  DB_PASSWORD_AD  - App user password (required for create-user)"
    echo "  (Also supports APP_DB_USER/APP_DB_PASSWORD)"
}

# Check command
if [[ $# -lt 1 ]]; then
    print_usage
    exit 1
fi

COMMAND="$1"
shift  # Remove command from args

# Run command
check_prerequisites

case "$COMMAND" in
    # Initial migration commands
    export)
        do_export
        ;;
    import)
        do_import
        ;;
    validate)
        do_validate
        ;;
    full)
        do_full
        ;;
    # Fresh setup commands
    fresh-setup)
        do_fresh_setup
        ;;
    schema)
        do_schema
        ;;
    seed)
        do_seed
        ;;
    # Incremental migration commands
    migration)
        do_migration "${1:-}"
        ;;
    all-migrations)
        do_all_migrations
        ;;
    # User management commands
    create-user)
        do_create_user
        ;;
    grant-permissions)
        do_grant_permissions
        ;;
    setup-app-user)
        do_setup_app_user
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        print_usage
        exit 1
        ;;
esac
