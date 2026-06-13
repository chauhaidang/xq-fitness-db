# XQ Fitness Database

Dockerized PostgreSQL 16 database for the XQ Fitness application. Owns the schema, seed data, numbered SQL migrations, Prisma client generation, smoke tests, and production deployment tooling.

**Repository:** [chauhaidang/xq-fitness-db](https://github.com/chauhaidang/xq-fitness-db)

[![Migrate Database to Neon](https://github.com/chauhaidang/xq-fitness-db/actions/workflows/migrate-to-neon.yml/badge.svg)](https://github.com/chauhaidang/xq-fitness-db/actions/workflows/migrate-to-neon.yml)

[![Publish Docker Image](https://github.com/chauhaidang/xq-fitness-db/actions/workflows/publish-docker.yml/badge.svg)](https://github.com/chauhaidang/xq-fitness-db/actions/workflows/publish-docker.yml)

## Overview

| Item | Value |
|------|-------|
| Engine | PostgreSQL 16 (Alpine) |
| Database name | `xq_fitness` |
| Tables | 9 (5 core + 4 snapshot) |
| Latest migration | `004_update_exercises_to_simplified_model.sql` |
| Schema source of truth | SQL files in `schemas/` + `migrations/` |
| Prisma role | Introspection and client generation only — **not** the migration tool |
| Consumers | `read-service` and `write-service` connect via raw `pg` (no Prisma in services) |

## Project Structure

```
database/
├── schemas/
│   ├── schema.sql              # Base DDL (core tables, triggers, indexes)
│   └── seed.sql                # Reference data (12 muscle groups)
├── migrations/
│   ├── 001_add_weekly_snapshots.sql
│   ├── 002_add_abductor_muscle_group.sql
│   ├── 003_add_exercises.sql
│   ├── 003_add_snapshot_exercises.sql
│   └── 004_update_exercises_to_simplified_model.sql   # latest
├── prisma/
│   └── schema.prisma           # Introspected from live DB (9 models)
├── generated/prisma/           # Generated Prisma client (gitignored)
├── tests/
│   └── smoke.test.ts           # 31 schema verification tests
├── scripts/
│   ├── build-docker.sh         # Build local Docker image
│   ├── migrate-to-neon.sh      # Apply schema/migrations to production
│   ├── create-app-user-neon.sql
│   └── grant-permissions-neon.sql
├── test-env/                   # xq-infra service configs
├── .github/workflows/
│   ├── publish-docker.yml
│   ├── migrate-to-neon.yml
│   └── publish-prisma-client.yml
├── Dockerfile
├── prisma.config.ts
├── package.json
└── jest.config.js
```

## Quick Start

### Build and run locally (Docker)

```bash
# Build image
cd scripts && ./build-docker.sh

# Or from repo root
docker build -t xq-fitness-db:latest .

# Run container
docker run -d \
  --name xq-fitness-db \
  -p 5432:5432 \
  -e POSTGRES_DB=xq_fitness \
  -e POSTGRES_USER=xq_user \
  -e POSTGRES_PASSWORD=xq_password \
  xq-fitness-db:latest
```

### Using xq-infra (with read/write services)

```bash
npm install -g @chauhaidang/xq-test-infra@1.0.3
xq-infra generate -f ./test-env
xq-infra up
```

Build `xq-fitness-db:latest` first — xq-infra expects the local image when using `database/test-env/`.

### Prisma client (for tests and npm consumers)

```bash
# Create .env with DATABASE_URL (see Environment Variables section)
npm install
npx prisma generate           # creates generated/prisma/
npm run test:smoke
```

## Local Connection

These are **local development defaults** baked into the Docker image. Do not use them in production.

| Setting | Value |
|---------|-------|
| Host | `localhost` (or `xq-fitness-db` inside Docker network) |
| Port | `5432` |
| Database | `xq_fitness` |
| User | `xq_user` |
| Password | `xq_password` |
| SSL | Not required locally |

Connection string format:

```
postgresql://<user>:<password>@<host>:<port>/<database>
```

Example for local Docker:

```
postgresql://xq_user:xq_password@localhost:5432/xq_fitness
```

## Docker Image Initialization

On first container start, PostgreSQL runs scripts from `/docker-entrypoint-initdb.d/` in order:

| Order | File | Purpose |
|-------|------|---------|
| 01 | `schemas/schema.sql` | Core tables, triggers, indexes |
| 02 | `schemas/seed.sql` | 12 muscle groups |
| 03 | `001_add_weekly_snapshots.sql` | Snapshot tables |
| 04 | `002_add_abductor_muscle_group.sql` | Abductor seed row |
| 05 | `003_add_exercises.sql` | `exercises` table (initial JSONB model) |
| 06 | `003_add_snapshot_exercises.sql` | `snapshot_exercises` table (initial JSONB model) |
| 07 | `004_update_exercises_to_simplified_model.sql` | **Latest** — simplified exercise columns |

> **Note:** `schemas/schema.sql` still defines `exercises` with a legacy `sets JSONB` column. Migration 004 removes that column at init time. For the current exercise shape, treat migration 004 or `prisma/schema.prisma` as authoritative.

## Schema (Current — 9 Tables)

### Entity relationships

```
muscle_groups
    ↑
    ├── workout_day_sets ←── workout_days ←── workout_routines
    ├── exercises      ←──┘
    ├── snapshot_workout_day_sets ←── snapshot_workout_days ←── weekly_snapshots ←── workout_routines
    └── snapshot_exercises ←──┘
```

### Core tables

#### `muscle_groups`

Reference table for target muscle groups.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | SERIAL | PRIMARY KEY |
| `name` | VARCHAR(100) | NOT NULL, UNIQUE |
| `description` | TEXT | |
| `created_at` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |

#### `workout_routines`

Workout program definitions.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | SERIAL | PRIMARY KEY |
| `name` | VARCHAR(200) | NOT NULL |
| `description` | TEXT | |
| `is_active` | BOOLEAN | DEFAULT true |
| `created_at` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| `updated_at` | TIMESTAMP | Auto-updated via trigger |

**Index:** `idx_routines_active` on `is_active`

#### `workout_days`

Days within a routine.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | SERIAL | PRIMARY KEY |
| `routine_id` | INTEGER | NOT NULL, FK → `workout_routines(id)` ON DELETE CASCADE |
| `day_number` | INTEGER | NOT NULL |
| `day_name` | VARCHAR(100) | NOT NULL |
| `notes` | TEXT | |
| `created_at` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| `updated_at` | TIMESTAMP | Auto-updated via trigger |

**Unique:** `(routine_id, day_number)`  
**Index:** `idx_workout_days_routine` on `routine_id`

#### `workout_day_sets`

Sets configuration per muscle group per workout day.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | SERIAL | PRIMARY KEY |
| `workout_day_id` | INTEGER | NOT NULL, FK → `workout_days(id)` ON DELETE CASCADE |
| `muscle_group_id` | INTEGER | NOT NULL, FK → `muscle_groups(id)` ON DELETE CASCADE |
| `number_of_sets` | INTEGER | NOT NULL, CHECK > 0 |
| `notes` | TEXT | |
| `created_at` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| `updated_at` | TIMESTAMP | Auto-updated via trigger |

**Unique:** `(workout_day_id, muscle_group_id)`  
**Indexes:** `idx_workout_day_sets_day`, `idx_workout_day_sets_muscle`

#### `exercises`

Individual exercise tracking per workout day. **Current model** (after migration 004):

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | SERIAL | PRIMARY KEY |
| `workout_day_id` | INTEGER | NOT NULL, FK → `workout_days(id)` ON DELETE CASCADE |
| `muscle_group_id` | INTEGER | NOT NULL, FK → `muscle_groups(id)` ON DELETE RESTRICT |
| `exercise_name` | VARCHAR(200) | NOT NULL, CHECK non-empty |
| `total_reps` | INTEGER | NOT NULL, DEFAULT 0, CHECK ≥ 0 |
| `weight` | DECIMAL(10,2) | NOT NULL, DEFAULT 0, CHECK ≥ 0 |
| `total_sets` | INTEGER | NOT NULL, DEFAULT 0, CHECK ≥ 0 |
| `notes` | TEXT | |
| `created_at` | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP |
| `updated_at` | TIMESTAMP | NOT NULL, auto-updated via trigger |

**Indexes:** `idx_exercises_workout_day`, `idx_exercises_muscle_group`, `idx_exercises_workout_day_muscle_group`

> Migration history: 003 introduced `sets JSONB`; 004 replaced it with `total_reps`, `weight`, `total_sets`.

### Snapshot tables

Weekly point-in-time captures of routine state. `original_*` columns store source IDs without FK constraints (allows historical reference after source deletion).

#### `weekly_snapshots`

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | SERIAL | PRIMARY KEY |
| `routine_id` | INTEGER | NOT NULL, FK → `workout_routines(id)` ON DELETE CASCADE |
| `week_start_date` | DATE | NOT NULL (Monday, ISO week) |
| `created_at` | TIMESTAMP | NOT NULL |
| `updated_at` | TIMESTAMP | Auto-updated via trigger |

**Unique:** `(routine_id, week_start_date)`  
**Indexes:** `idx_weekly_snapshots_routine`, `idx_weekly_snapshots_week_start`

#### `snapshot_workout_days`

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | SERIAL | PRIMARY KEY |
| `snapshot_id` | INTEGER | NOT NULL, FK → `weekly_snapshots(id)` ON DELETE CASCADE |
| `original_workout_day_id` | INTEGER | NOT NULL (no FK) |
| `day_number` | INTEGER | NOT NULL |
| `day_name` | VARCHAR(100) | NOT NULL |
| `notes` | TEXT | |
| `created_at` | TIMESTAMP | NOT NULL |

**Unique:** `(snapshot_id, day_number)`  
**Index:** `idx_snapshot_workout_days_snapshot`

#### `snapshot_workout_day_sets`

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | SERIAL | PRIMARY KEY |
| `snapshot_workout_day_id` | INTEGER | NOT NULL, FK → `snapshot_workout_days(id)` ON DELETE CASCADE |
| `original_workout_day_set_id` | INTEGER | NOT NULL (no FK) |
| `muscle_group_id` | INTEGER | NOT NULL, FK → `muscle_groups(id)` ON DELETE RESTRICT |
| `number_of_sets` | INTEGER | NOT NULL, CHECK > 0 |
| `notes` | TEXT | |
| `created_at` | TIMESTAMP | NOT NULL |

**Unique:** `(snapshot_workout_day_id, muscle_group_id)`  
**Indexes:** `idx_snapshot_workout_day_sets_day`, `idx_snapshot_workout_day_sets_muscle`

#### `snapshot_exercises`

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | SERIAL | PRIMARY KEY |
| `snapshot_workout_day_id` | INTEGER | NOT NULL, FK → `snapshot_workout_days(id)` ON DELETE CASCADE |
| `original_exercise_id` | INTEGER | NOT NULL (no FK) |
| `exercise_name` | VARCHAR(200) | NOT NULL |
| `muscle_group_id` | INTEGER | NOT NULL, FK → `muscle_groups(id)` ON DELETE RESTRICT |
| `total_reps` | INTEGER | NOT NULL, DEFAULT 0, CHECK ≥ 0 |
| `weight` | DECIMAL(10,2) | NOT NULL, DEFAULT 0, CHECK ≥ 0 |
| `total_sets` | INTEGER | NOT NULL, DEFAULT 0, CHECK ≥ 0 |
| `notes` | TEXT | |
| `created_at` | TIMESTAMP | NOT NULL |

**Indexes:** `idx_snapshot_exercises_snapshot_workout_day`, `idx_snapshot_exercises_muscle_group`

## Migration History

| File | Date | Description |
|------|------|-------------|
| `001_add_weekly_snapshots.sql` | 2024-12-07 | Adds `weekly_snapshots`, `snapshot_workout_days`, `snapshot_workout_day_sets` |
| `002_add_abductor_muscle_group.sql` | 2025-12-23 | Seeds Abductor muscle group |
| `003_add_exercises.sql` | 2025-01-27 | Adds `exercises` with `sets JSONB` |
| `003_add_snapshot_exercises.sql` | 2025-01-27 | Adds `snapshot_exercises` with `sets JSONB` |
| `004_update_exercises_to_simplified_model.sql` | 2025-01-27 | Replaces JSONB `sets` with `total_reps`, `weight`, `total_sets` on both exercise tables |

All migrations use idempotent DDL (`IF NOT EXISTS`, `DROP … IF EXISTS`) where applicable.

## Seed Data

`schemas/seed.sql` inserts 12 muscle groups:

Chest, Back, Shoulders, Biceps, Triceps, Forearms, Quadriceps, Hamstrings, Glutes, Calves, Abs, Lower Back

Migration 002 adds a 13th:

Abductor — hip abductor muscles (gluteus medius, gluteus minimus, tensor fasciae latae)

Rows use `ON CONFLICT (name) DO NOTHING` for safe re-runs.

## Schema Features

### Triggers

`update_updated_at_column()` function auto-updates `updated_at` on:

- `workout_routines`
- `workout_days`
- `workout_day_sets`
- `exercises`
- `weekly_snapshots`

### Delete behavior

| Parent | Child | ON DELETE |
|--------|-------|-----------|
| `workout_routines` | `workout_days`, `weekly_snapshots` | CASCADE |
| `workout_days` | `workout_day_sets`, `exercises` | CASCADE |
| `muscle_groups` | `workout_day_sets` | CASCADE |
| `muscle_groups` | `exercises`, snapshot tables | RESTRICT |
| `weekly_snapshots` | `snapshot_workout_days` | CASCADE |
| `snapshot_workout_days` | `snapshot_workout_day_sets`, `snapshot_exercises` | CASCADE |

### Health check

```bash
docker inspect --format='{{.State.Health.Status}}' xq-fitness-db
```

Uses `pg_isready` every 10s (30s start period).

## Prisma Integration

Prisma is used for **client generation and introspection**, not schema migrations.

| File | Purpose |
|------|---------|
| `prisma/schema.prisma` | 9 models introspected from live DB |
| `prisma.config.ts` | Reads `DATABASE_URL` from environment |
| `generated/prisma/` | Generated client output (gitignored) |
| `package.generated.json` | Published npm package metadata |

### Generator config

```prisma
generator client {
  provider               = "prisma-client"
  output                 = "../generated/prisma"
  moduleFormat           = "cjs"
  generatedFileExtension = "ts"
}
```

`moduleFormat = "cjs"` is required for Jest compatibility with Prisma v7.

### Prisma v7 usage (requires driver adapter)

```typescript
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../generated/prisma/client";

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });
const prisma = new PrismaClient({ adapter });
```

### Common commands

```bash
npx prisma generate    # Regenerate client after schema.prisma changes
npx prisma db pull     # Introspect live DB → update schema.prisma
npx prisma studio      # Visual DB browser
npx prisma validate    # Validate schema file
```

### Published npm package

`@chauhaidang/xq-fitness-db-client` — published to GitHub Packages when `prisma/schema.prisma` or `package.generated.json` version changes. Peer dependencies: `@prisma/client`, `@prisma/adapter-pg`.

## Testing

### Stack

- **Jest** with `--forceExit` (connection cleanup)
- **@swc/jest** — required; generated Prisma types are too large for ts-jest
- **Prisma Client** — type-safe queries in smoke tests

### Run tests

```bash
# Database must be running on localhost:5432
npx prisma generate
npm run test:smoke    # 31 tests
npm test              # all tests in tests/
```

### Smoke test coverage

- Database connectivity (`xq_fitness`)
- All 9 tables exist
- Per-table: queryability, field structure, relations, unique constraints, check constraints, indexes, triggers

## Service Integration

`read-service` and `write-service` do **not** use Prisma. They connect with raw `pg` using these environment variables:

| Variable | Local default |
|----------|---------------|
| `DB_HOST` | `localhost` |
| `DB_PORT` | `5432` |
| `DB_NAME` | `xq_fitness` |
| `DB_USER` | `xq_user` |
| `DB_PASSWORD` | `xq_password` |
| `DB_SSL` | `'false'` locally; enabled in production unless set to `'false'` |

Inside xq-infra, `DB_HOST` is set to the database container name (`xq-fitness-db`).

## CI/CD

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `publish-docker.yml` | Push to `main`, manual | Build and push `ghcr.io/<owner>/xq-fitness-db:<git-hash>` and `:latest` |
| `migrate-to-neon.yml` | Manual only | Apply schema/seed/migrations to production Neon |
| `publish-prisma-client.yml` | Push to `main` (schema changes), manual | Publish `@chauhaidang/xq-fitness-db-client` to GitHub Packages |

### Published Docker image

```bash
docker pull ghcr.io/<owner>/xq-fitness-db:latest
```

Tags: `<git-short-hash>` (immutable) and `latest`.

## Production (Neon)

Production uses Neon serverless PostgreSQL. Credentials are **never** stored in this repository — configure them via environment variables or GitHub Actions secrets.

### Required secrets (GitHub Actions)

| Secret | Purpose |
|--------|---------|
| `NEON_DATABASE_URL` | Neon connection string (`?sslmode=require`) |
| `DB_USER_AD` | Application database user name (optional, for user-management modes) |
| `DB_PASSWORD_AD` | Application database user password (optional) |

### Migration modes

Via Actions → **Migrate Database to Neon** (manual, requires typing `yes` to confirm):

| Mode | Action |
|------|--------|
| `schema` | Apply `schemas/schema.sql` only |
| `seed` | Apply `schemas/seed.sql` only |
| `fresh-setup` | Schema + seed + all migrations |
| `all-migrations` | Apply all files in `migrations/` |
| `migration` | Apply a single named migration file |
| `validate` | Verify connection and schema state |
| `create-user` | Create application DB user |
| `grant-permissions` | Grant permissions to application user |
| `setup-app-user` | Create user and grant permissions |

### Local production migration script

Set credentials via environment variables — do not commit them:

```bash
export NEON_DATABASE_URL="postgresql://<user>:<password>@<host>/<database>?sslmode=require"

cd scripts
./migrate-to-neon.sh fresh-setup       # New database: schema + seed + migrations
./migrate-to-neon.sh all-migrations    # Apply all migration files
./migrate-to-neon.sh migration 004_update_exercises_to_simplified_model.sql
```

Optional app user setup:

```bash
export DB_USER_AD=<app_user>
export DB_PASSWORD_AD=<app_password>
./migrate-to-neon.sh setup-app-user
```

> Copy `scripts/env.neon` to a local `.env.neon` (gitignored) and fill in your own values. **Never commit real credentials.**

## Adding a New Migration

1. Create `migrations/NNN_description.sql` with idempotent DDL.
2. Add a `COPY` line in `Dockerfile` (next `0N-*.sql` in init order).
3. Apply against a local database and verify.
4. Run `npx prisma db pull` to update `prisma/schema.prisma`.
5. Run `npx prisma generate` to regenerate the client.
6. Update `tests/smoke.test.ts` if tables, columns, or constraints changed.
7. Bump version in `package.generated.json` if publishing the Prisma client.
8. Commit and push — CI publishes the updated Docker image.

## Environment Variables

Create a local `.env` file (gitignored). Never commit production credentials.

| Variable | Scope | Description |
|----------|-------|-------------|
| `DATABASE_URL` | Local dev / tests | Full PostgreSQL connection string for Prisma and smoke tests |
| `NEON_DATABASE_URL` | Production migrations | Neon connection string with SSL |
| `NEON_DB_HOST`, `NEON_DB_PORT`, `NEON_DB_USER`, `NEON_DB_PASSWORD`, `NEON_DB_NAME` | Production migrations | Alternative to `NEON_DATABASE_URL` |
| `DB_USER_AD`, `DB_PASSWORD_AD` | Production user setup | Application-scoped DB user (not owner account) |
| `GITHUB_TOKEN` | CI / npm | GitHub Packages auth for Prisma client publish |

Example local `.env` (development defaults only):

```env
DATABASE_URL=postgresql://xq_user:xq_password@localhost:5432/xq_fitness?schema=public
```

## Customization

To change local Docker defaults, update `ENV` variables in `Dockerfile` and matching service `test-env` configs. For production, use Neon secrets and the migration tooling — do not reuse local dev credentials.
