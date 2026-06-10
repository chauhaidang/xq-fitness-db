# XQ Fitness Database Container

This directory contains a Dockerized PostgreSQL database for the XQ Fitness application, pre-populated with schema and seed data and all upcoming migrations

[![Migrate Database to Neon](https://github.com/chauhaidang/xq-fitness-db/actions/workflows/migrate-to-neon.yml/badge.svg)](https://github.com/chauhaidang/xq-fitness-db/actions/workflows/migrate-to-neon.yml)

[![Publish Docker Image](https://github.com/chauhaidang/xq-fitness-db/actions/workflows/publish-docker.yml/badge.svg)](https://github.com/chauhaidang/xq-fitness-db/actions/workflows/publish-docker.yml)

## Quick Start

### Local Testing Workflow

For local development and testing, use the provided build and run scripts:

```bash
# Build the Docker image
cd scripts
./build-docker.sh

# Start the database container (manual option)
./run-docker-local.sh

# Or use xq-infra to spin up the database locally
# (xq-infra will use the xq-fitness-db:latest image)
```

The build script (`build-docker.sh`) will:
- Verify Docker is installed and running
- Build the image with tag `xq-fitness-db:latest`
- Display build progress and success message

The run script (`run-docker-local.sh`) will:
- Check if container already exists and handle cleanup
- Start the container with name `xq-fitness-db-local` on port 5432
- Display connection information after container starts

**Note**: For automated local testing, use `xq-infra` to spin up the database. The build script creates the `xq-fitness-db:latest` image that xq-infra expects.

### Using Docker CLI (Manual)

```bash
# Build the image
docker build -t xq-fitness-db:latest .

# Run the container
docker run -d \
  --name xq-fitness-db \
  -p 5432:5432 \
  -e POSTGRES_DB=xq_fitness \
  -e POSTGRES_USER=xq_user \
  -e POSTGRES_PASSWORD=xq_password \
  xq-fitness-db:latest

# View logs
docker logs -f xq-fitness-db

# Stop and remove the container
docker stop xq-fitness-db && docker rm xq-fitness-db
```

## Database Connection

Once the container is running, connect using:

- **Host**: `localhost` (or `xq-fitness-db` from within Docker network)
- **Port**: `5432`
- **Database**: `xq_fitness`
- **User**: `xq_user`
- **Password**: `xq_password`

### Connection String

```
postgresql://xq_user:xq_password@localhost:5432/xq_fitness
```

## Database Schema

The database includes the following tables:

### Core Tables
- `muscle_groups` - Reference table for muscle groups
- `workout_routines` - Workout routine definitions
- `workout_days` - Individual days within a routine
- `workout_day_sets` - Sets configuration for muscle groups per day

### Snapshot Tables
- `weekly_snapshots` - Weekly snapshots of workout routines
- `snapshot_workout_days` - Workout days captured in snapshots
- `snapshot_workout_day_sets` - Sets configuration captured in snapshots

### Schema Features
- **Indexes**: Optimized indexes on foreign keys and frequently queried columns
- **Triggers**: Automatic `updated_at` timestamp management for relevant tables
- **Constraints**: Unique constraints and foreign key relationships ensure data integrity
- **Cascade Deletes**: Related records are automatically cleaned up when parent records are deleted

### Table Relationships

**Core Workout Structure:**
```
workout_routines (1) → (N) workout_days (1) → (N) workout_day_sets (N) → (1) muscle_groups
```

**Snapshot Structure:**
```
weekly_snapshots (1) → (N) snapshot_workout_days (1) → (N) snapshot_workout_day_sets (N) → (1) muscle_groups
```

### Table Details

#### Core Tables

**muscle_groups**
- `id` (SERIAL PRIMARY KEY) - Unique identifier
- `name` (VARCHAR(100) UNIQUE) - Muscle group name
- `description` (TEXT) - Optional description
- `created_at` (TIMESTAMP) - Creation timestamp

**workout_routines**
- `id` (SERIAL PRIMARY KEY) - Unique identifier
- `name` (VARCHAR(200)) - Routine name
- `description` (TEXT) - Optional description
- `is_active` (BOOLEAN) - Active status flag
- `created_at` (TIMESTAMP) - Creation timestamp
- `updated_at` (TIMESTAMP) - Last update timestamp (auto-managed)

**workout_days**
- `id` (SERIAL PRIMARY KEY) - Unique identifier
- `routine_id` (INTEGER FK → workout_routines.id) - Parent routine
- `day_number` (INTEGER) - Day number within routine
- `day_name` (VARCHAR(100)) - Day name
- `notes` (TEXT) - Optional notes
- `created_at` (TIMESTAMP) - Creation timestamp
- `updated_at` (TIMESTAMP) - Last update timestamp (auto-managed)
- **Constraint**: Unique `(routine_id, day_number)`

**workout_day_sets**
- `id` (SERIAL PRIMARY KEY) - Unique identifier
- `workout_day_id` (INTEGER FK → workout_days.id) - Parent workout day
- `muscle_group_id` (INTEGER FK → muscle_groups.id) - Target muscle group
- `number_of_sets` (INTEGER CHECK > 0) - Number of sets
- `notes` (TEXT) - Optional notes
- `created_at` (TIMESTAMP) - Creation timestamp
- `updated_at` (TIMESTAMP) - Last update timestamp (auto-managed)
- **Constraint**: Unique `(workout_day_id, muscle_group_id)`

#### Snapshot Tables

**weekly_snapshots**
- `id` (SERIAL PRIMARY KEY) - Unique identifier
- `routine_id` (INTEGER FK → workout_routines.id) - Snapshot routine reference
- `week_start_date` (DATE) - Monday date of the week (ISO 8601)
- `created_at` (TIMESTAMP) - Snapshot creation timestamp
- `updated_at` (TIMESTAMP) - Last update timestamp (auto-managed)
- **Constraint**: Unique `(routine_id, week_start_date)`

**snapshot_workout_days**
- `id` (SERIAL PRIMARY KEY) - Unique identifier
- `snapshot_id` (INTEGER FK → weekly_snapshots.id) - Parent snapshot
- `original_workout_day_id` (INTEGER) - Reference to original workout_day.id (no FK constraint)
- `day_number` (INTEGER) - Day number within routine
- `day_name` (VARCHAR(100)) - Day name at snapshot time
- `notes` (TEXT) - Optional notes
- `created_at` (TIMESTAMP) - Snapshot creation timestamp
- **Constraint**: Unique `(snapshot_id, day_number)`

**snapshot_workout_day_sets**
- `id` (SERIAL PRIMARY KEY) - Unique identifier
- `snapshot_workout_day_id` (INTEGER FK → snapshot_workout_days.id) - Parent snapshot day
- `original_workout_day_set_id` (INTEGER) - Reference to original workout_day_set.id (no FK constraint)
- `muscle_group_id` (INTEGER FK → muscle_groups.id) - Target muscle group
- `number_of_sets` (INTEGER CHECK > 0) - Number of sets at snapshot time
- `notes` (TEXT) - Optional notes
- `created_at` (TIMESTAMP) - Snapshot creation timestamp
- **Constraint**: Unique `(snapshot_workout_day_id, muscle_group_id)`

## Initial Data

The database comes pre-populated with:

- **13 muscle groups**: Chest, Back, Shoulders, Biceps, Triceps, Forearms, Quadriceps, Hamstrings, Glutes, Calves, Abs, Lower Back, Abductor

## Customization

To modify default credentials, update the environment variables in:

- `Dockerfile` (ENV variables)

## Health Check

The container includes a health check that verifies PostgreSQL is ready:

```bash
docker inspect --format='{{.State.Health.Status}}' xq-fitness-db
```

## Publishing to GitHub Container Registry

### Automated Publishing with GitHub Actions

The repository includes a GitHub Actions workflow (`.github/workflows/publish-docker.yml`) that automatically publishes the image when:

- **Push to main/master branch** - Publishes with git hash tag and updates `latest`
- **Manual trigger** - Run workflow manually from GitHub Actions tab

Each push will automatically build and publish:
- `ghcr.io/YOUR_USERNAME/xq-fitness-db:<git-hash>` - Immutable version (e.g., `abc1234`)
- `ghcr.io/YOUR_USERNAME/xq-fitness-db:latest` - Always points to the latest push

#### Example

```bash
# Push a commit
git push origin main
```

This will automatically publish:
- `ghcr.io/YOUR_USERNAME/xq-fitness-db:abc1234` (git hash)
- `ghcr.io/YOUR_USERNAME/xq-fitness-db:latest` (updated to same image)

### Using the Published Image

```bash
# Pull from GitHub Container Registry
docker pull ghcr.io/YOUR_USERNAME/xq-fitness-db:latest

# Run the published image
docker run -d \
  --name xq-fitness-db \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=your_secure_password \
  ghcr.io/YOUR_USERNAME/xq-fitness-db:latest
```

## Production Database (Neon)

Production uses Neon serverless PostgreSQL. Apply schema, seed data, and migrations via GitHub Actions or the local script.

### Using GitHub Actions (Recommended)

1. Add secrets to GitHub (Settings → Secrets → Actions):
   - `NEON_DATABASE_URL` — Neon connection string
   - `DB_USER_AD`, `DB_PASSWORD_AD` — app user credentials (for user-management modes)
2. Go to Actions → **Migrate Database to Neon**
3. Click **Run workflow** → Choose mode → Type "yes" → **Run**

Available modes: `schema`, `seed`, `fresh-setup`, `migration`, `all-migrations`, `validate`, `create-user`, `grant-permissions`, `setup-app-user`.

### Using Local Script

```bash
export NEON_DATABASE_URL="postgresql://user:password@host/db?sslmode=require"

cd scripts
./migrate-to-neon.sh schema          # Apply schema.sql only
./migrate-to-neon.sh seed              # Apply seed.sql only
./migrate-to-neon.sh all-migrations    # Apply all migration files
./migrate-to-neon.sh fresh-setup       # Schema + seed + all migrations
./migrate-to-neon.sh migration 005_example.sql  # Single migration file
```

For app user setup, set `DB_USER_AD` and `DB_PASSWORD_AD`, then run `./migrate-to-neon.sh setup-app-user`.

