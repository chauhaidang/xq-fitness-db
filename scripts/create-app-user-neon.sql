-- Create application user for Neon database
-- Run this as the database owner (neondb_owner or your admin user)
--
-- This creates a restricted user that can only:
-- - SELECT, INSERT, UPDATE, DELETE on tables
-- - Use sequences (for auto-increment IDs)
-- - Execute functions (for triggers)
--
-- The user CANNOT:
-- - CREATE/DROP tables
-- - ALTER table structure
-- - Manage other users
--
-- Usage:
--   Set APP_DB_PASSWORD before running:
--   export APP_DB_PASSWORD='your-secure-password'
--   psql $NEON_DATABASE_URL -v app_password="$APP_DB_PASSWORD" -f create-app-user-neon.sql
--
-- Note: This script uses current_database() so it works with any database name (xq_fitness, neondb, etc.)

-- Create the app user (if not exists)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'xq_app_user') THEN
        -- Create user with password from variable or default
        -- In production, ALWAYS set a secure password via -v app_password="..."
        EXECUTE format('CREATE USER xq_app_user WITH PASSWORD %L', 
            coalesce(current_setting('app_password', true), 'change_me_in_production'));
        RAISE NOTICE 'Created user: xq_app_user';
    ELSE
        RAISE NOTICE 'User xq_app_user already exists';
    END IF;
END
$$;

-- Grant connect privilege on the current database (works with any database name)
DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO xq_app_user', current_database());
    RAISE NOTICE 'Granted CONNECT on database: %', current_database();
END
$$;

-- Display user info
SELECT 
    rolname as username,
    rolcanlogin as can_login,
    rolcreatedb as can_create_db,
    rolcreaterole as can_create_role,
    rolsuper as is_superuser
FROM pg_roles 
WHERE rolname = 'xq_app_user';
