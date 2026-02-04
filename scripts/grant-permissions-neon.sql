-- Grant database permissions to app user for Neon
-- Run this as the database owner (neondb_owner or your admin user) after tables are created
-- 
-- Usage:
--   1. Set APP_DB_USER environment variable (default: xq_app_user)
--   2. Run: psql $NEON_DATABASE_URL -f grant-permissions-neon.sql
--
-- Note: User must be created first using create-app-user-neon.sql
-- Note: This script works with any database name (xq_fitness, neondb, etc.)

-- Grant schema usage
GRANT USAGE ON SCHEMA public TO xq_app_user;

-- Grant permissions on all existing tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO xq_app_user;

-- Grant permissions on all sequences (for SERIAL columns like id)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO xq_app_user;

-- Grant execute permission on functions (for triggers)
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO xq_app_user;

-- Set default privileges for future tables (so new tables automatically get permissions)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO xq_app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO xq_app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO xq_app_user;

-- Verify permissions (shows what was granted)
SELECT 
    'Tables' as type,
    tablename as name,
    has_table_privilege('xq_app_user', schemaname||'.'||tablename, 'SELECT') as can_select,
    has_table_privilege('xq_app_user', schemaname||'.'||tablename, 'INSERT') as can_insert,
    has_table_privilege('xq_app_user', schemaname||'.'||tablename, 'UPDATE') as can_update,
    has_table_privilege('xq_app_user', schemaname||'.'||tablename, 'DELETE') as can_delete
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY tablename;
