# Database Migration to DigitalOcean

This guide explains how to migrate the XQ Fitness database schema and seed data to DigitalOcean PostgreSQL.

## Overview

The database repository provides two ways to migrate your database:

1. **Local Script** - Run migrations from your local machine
2. **GitHub Actions** - Trigger migrations via GitHub workflow

## Prerequisites

### For Local Migration
- PostgreSQL client (`psql`) installed
- Database connection details from DigitalOcean
- Access to the database repository

### For GitHub Actions
- Database connection details added as GitHub Secrets
- Write access to the repository

## Setup

### 1. Configure GitHub Secrets

Add the following secrets to your GitHub repository (Settings → Secrets → Actions):

| Secret Name | Description | Example |
|------------|-------------|---------|
| `DB_HOST` | Database host from DigitalOcean | `xq-fitness-db-do-user-123-0.db.ondigitalocean.com` |
| `DB_PORT` | Database port | `25060` |
| `DB_USER` | Database user | `xq_app_user` |
| `DB_PASSWORD` | Database password | `your-secure-password` |
| `DB_NAME` | Database name | `xq_fitness` |

### 2. Get Database Connection Details

If you've already provisioned the database using the deployment scripts:

```bash
# From read-service or write-service repository
cd deploy/digitalocean
export DO_TOKEN=your_digitalocean_token
./provision-db.sh
```

The script will output connection details you need for the secrets above.

## Local Migration

### Using the Migration Script

```bash
# Navigate to database repository
cd database/scripts

# Set environment variables
export DB_HOST=your-db-host
export DB_PORT=25060
export DB_USER=xq_app_user
export DB_PASSWORD=your-secure-password
export DB_NAME=xq_fitness

# Run full migration (schema + seed)
./migrate-to-do.sh

# Or run schema only
./migrate-to-do.sh --schema-only

# Or run seed data only
./migrate-to-do.sh --seed-only
```

### What the Script Does

1. **Tests connection** - Verifies it can connect to the database
2. **Applies schema** - Creates tables, indexes, triggers, and functions
3. **Applies seed data** - Inserts initial muscle groups
4. **Verifies migration** - Checks table count and shows summary

### Troubleshooting Local Migration

**Error: "psql: command not found"**
- Install PostgreSQL client:
  - macOS: `brew install postgresql`
  - Ubuntu: `sudo apt-get install postgresql-client`
  - Windows: Download from [postgresql.org](https://www.postgresql.org/download/windows/)

**Error: "connection refused"**
- Verify your database host and port
- Check if your IP is whitelisted in DigitalOcean (Databases → Settings → Trusted Sources)

**Error: "relation already exists"**
- Tables already exist - this is usually safe to ignore
- If you need to reset: manually drop tables or use `--seed-only` to just add seed data

## GitHub Actions Migration

### Triggering the Workflow

1. Go to your repository on GitHub
2. Click **Actions** tab
3. Select **Migrate Database to DigitalOcean** workflow
4. Click **Run workflow**
5. Choose migration mode:
   - **full** - Apply schema and seed data (recommended for first-time setup)
   - **schema-only** - Apply only table definitions
   - **seed-only** - Apply only seed data
6. Type **yes** in the confirmation field
7. Click **Run workflow**

### Migration Modes

| Mode | When to Use |
|------|-------------|
| `full` | First-time database setup, or complete reset |
| `schema-only` | Schema changes without affecting existing data |
| `seed-only` | Add reference data to existing tables |

### Monitoring the Workflow

- The workflow shows real-time progress in the Actions tab
- Successful migration will show:
  - ✓ Connection test passed
  - ✓ Schema applied
  - ✓ Seed data applied
  - Table count and row counts
- Failed migrations will show detailed error logs

## Migration Files

### Schema (`schemas/schema.sql`)

Creates the core database structure:
- `muscle_groups` - Reference table for muscle groups
- `workout_routines` - Workout routine definitions
- `workout_days` - Days within a routine
- `workout_day_sets` - Sets configuration per muscle group
- Indexes for performance
- Triggers for auto-updating timestamps

### Migrations (`migrations/`)

Additional schema changes applied via migration files:
- `001_add_weekly_snapshots.sql` - Adds weekly snapshot tables (`weekly_snapshots`, `snapshot_workout_days`, `snapshot_workout_day_sets`)
- `002_add_abductor_muscle_group.sql` - Adds Abductor muscle group to seed data

### Seed Data (`schemas/seed.sql`)

Inserts initial reference data:
- 12 muscle groups (Chest, Back, Shoulders, Biceps, Triceps, Forearms, Quadriceps, Hamstrings, Glutes, Calves, Abs, Lower Back)
- Migration `002_add_abductor_muscle_group.sql` adds the 13th muscle group (Abductor)

## Best Practices

### First-Time Setup
1. Provision the database using `provision-db.sh`
2. Add GitHub Secrets
3. Run GitHub Actions workflow with **full** mode
4. Verify tables were created successfully

### Making Schema Changes
1. Update `schemas/schema.sql` with new changes
2. Test locally first using `migrate-to-do.sh`
3. Commit changes to repository
4. Run GitHub Actions workflow with **schema-only** mode

### Adding New Seed Data
1. Update `schemas/seed.sql`
2. Run GitHub Actions workflow with **seed-only** mode

### Production Considerations
- **Always backup** before running migrations in production
- Test migrations on a staging database first
- Use `--schema-only` for schema changes to avoid data loss
- Consider using migration tools like Flyway or Liquibase for production

## Verifying Migration

### Check Tables

```bash
export PGPASSWORD=$DB_PASSWORD
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "\dt"
```

### Check Seed Data

```bash
export PGPASSWORD=$DB_PASSWORD
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "SELECT * FROM muscle_groups;"
```

### Expected Result

After a successful full migration, you should see:
- **7 tables**: 
  - Core: `muscle_groups`, `workout_routines`, `workout_days`, `workout_day_sets`
  - Snapshots: `weekly_snapshots`, `snapshot_workout_days`, `snapshot_workout_day_sets`
- **13 rows in `muscle_groups`** (12 from seed + 1 from migration)
- Various indexes and triggers

## Rollback

To rollback a migration:

```bash
# Drop all tables (WARNING: This deletes all data!)
export PGPASSWORD=$DB_PASSWORD
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << EOF
DROP TABLE IF EXISTS snapshot_workout_day_sets CASCADE;
DROP TABLE IF EXISTS snapshot_workout_days CASCADE;
DROP TABLE IF EXISTS weekly_snapshots CASCADE;
DROP TABLE IF EXISTS workout_day_sets CASCADE;
DROP TABLE IF EXISTS workout_days CASCADE;
DROP TABLE IF EXISTS workout_routines CASCADE;
DROP TABLE IF EXISTS muscle_groups CASCADE;
DROP FUNCTION IF EXISTS update_updated_at_column();
EOF
```

Then re-run the migration.

## Support

For issues or questions:
1. Check the workflow logs in GitHub Actions
2. Review the error messages from `psql`
3. Verify connection details and GitHub Secrets
4. Ensure your IP is whitelisted in DigitalOcean

## Related Documentation

- [DigitalOcean Managed PostgreSQL Docs](https://docs.digitalocean.com/products/databases/postgresql/)
- [Deployment Guide](../deploy/digitalocean/README.md)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

