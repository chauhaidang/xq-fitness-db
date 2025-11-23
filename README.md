# XQ Fitness Database Container

This directory contains a Dockerized PostgreSQL database for the XQ Fitness application, pre-populated with schema and seed data.

## Quick Start

### Using Docker CLI

```bash
# Build the image
docker build -t xq-fitness-db .

# Run the container
docker run -d \
  --name xq-fitness-db \
  -p 5432:5432 \
  -e POSTGRES_DB=xq_fitness \
  -e POSTGRES_USER=xq_user \
  -e POSTGRES_PASSWORD=xq_password \
  xq-fitness-db

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

- `muscle_groups` - Reference table for muscle groups
- `workout_routines` - Workout routine definitions
- `workout_days` - Individual days within a routine
- `workout_day_sets` - Sets configuration for muscle groups per day

## Initial Data

The database comes pre-populated with:

- 12 muscle groups (Chest, Back, Shoulders, Biceps, Triceps, Forearms, Quadriceps, Hamstrings, Glutes, Calves, Abs, Lower Back)

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

## Migrating to DigitalOcean

For production deployment, migrate the schema and seed data to DigitalOcean PostgreSQL:

### Using GitHub Actions (Recommended)

1. Add database connection secrets to GitHub (Settings → Secrets → Actions):
   - `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`
2. Go to Actions → **Migrate Database to DigitalOcean**
3. Click **Run workflow** → Choose mode → Type "yes" → **Run**

### Using Local Script

```bash
# Set environment variables
export DB_HOST=your-db-host
export DB_PORT=25060
export DB_USER=xq_app_user
export DB_PASSWORD=your-password
export DB_NAME=xq_fitness

# Run migration
cd scripts
./migrate-to-do.sh

# Or schema only / seed only
./migrate-to-do.sh --schema-only
./migrate-to-do.sh --seed-only
```

See [MIGRATION.md](./MIGRATION.md) for detailed migration documentation.

