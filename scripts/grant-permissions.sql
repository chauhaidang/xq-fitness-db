-- Grant database permissions to app user
-- Run this as the database admin user (doadmin) after tables are created

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

-- Verify permissions (optional - shows what was granted)
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

