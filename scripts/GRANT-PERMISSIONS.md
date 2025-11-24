# Grant Database Permissions

## Problem

If you're seeing errors like:
```
Error creating routine: error: permission denied for table workout_routines
```

This means the database user (`xq_app_user`) doesn't have permissions on the tables. The tables exist, but the user can't INSERT, UPDATE, DELETE, or SELECT from them.

## Solution

You need to grant permissions to the `xq_app_user` on all tables. There are several ways to do this:

### Option 1: Using the grant-permissions.sh script (Recommended)

```bash
cd database/scripts

# Set your DigitalOcean token
export DO_TOKEN=your_digitalocean_token

# Set the database admin password (doadmin user)
# You can find this in DigitalOcean dashboard or reset it
export DB_PASSWORD=your_doadmin_password

# Run the script
./grant-permissions.sh
```

**Note:** This requires:
- `psql` (PostgreSQL client) installed
- Your IP address whitelisted in the database firewall rules
- The password for the `doadmin` user

### Option 2: Using DigitalOcean Console (Easiest)

1. Go to your DigitalOcean dashboard
2. Navigate to Databases → Your cluster → **Users & Databases** tab
3. Click on your database name (`xq_fitness`)
4. Click **"Query"** tab
5. Connect as the `doadmin` user
6. Copy and paste the contents of `scripts/grant-permissions.sql`
7. Execute the SQL

### Option 3: Using psql directly

```bash
# Get connection details first
export DO_TOKEN=your_token
doctl auth init -t "$DO_TOKEN"

# Get cluster ID
DB_CLUSTER_ID=$(doctl databases list --output json | jq -r '.[] | select(.name=="xq-fitness-db") | .id')

# Get connection string
doctl databases connection "$DB_CLUSTER_ID" --format ConnectionURI

# Connect and run SQL
psql "postgresql://doadmin:PASSWORD@HOST:PORT/xq_fitness?sslmode=require" -f scripts/grant-permissions.sql
```

Replace:
- `PASSWORD` with your doadmin password
- `HOST` and `PORT` with values from the connection string

### Option 4: Quick fix via SQL

If you have access to the database console, run these commands as the `doadmin` user:

```sql
-- Grant schema usage
GRANT USAGE ON SCHEMA public TO xq_app_user;

-- Grant permissions on all tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO xq_app_user;

-- Grant permissions on sequences (for auto-increment IDs)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO xq_app_user;

-- Grant execute on functions (for triggers)
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO xq_app_user;

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO xq_app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO xq_app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO xq_app_user;
```

## Verify Permissions

After granting permissions, you can verify with:

```sql
SELECT 
    tablename,
    has_table_privilege('xq_app_user', 'public.'||tablename, 'SELECT') as can_select,
    has_table_privilege('xq_app_user', 'public.'||tablename, 'INSERT') as can_insert,
    has_table_privilege('xq_app_user', 'public.'||tablename, 'UPDATE') as can_update,
    has_table_privilege('xq_app_user', 'public.'||tablename, 'DELETE') as can_delete
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY tablename;
```

All columns should show `t` (true) for the tables:
- `muscle_groups`
- `workout_routines`
- `workout_days`
- `workout_day_sets`

## Why This Happens

When you create a database user via DigitalOcean's API (`doctl databases user create`), the user is created but doesn't automatically get permissions on existing tables. You need to explicitly grant permissions.

## Prevention

To prevent this in the future, you can:
1. Grant permissions immediately after creating the user
2. Use the `grant-permissions.sql` script as part of your database setup
3. Include permission grants in your database migration scripts

