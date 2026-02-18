# XQ Fitness Database — Agent Guide

## Overview

Dockerized PostgreSQL 16 database for the XQ Fitness application. Contains schema definitions, seed data, sequential SQL migrations, Prisma ORM integration, and smoke tests.

**Repository**: `chauhaidang/xq-fitness-db`

## Project Structure

```
database/
├── schemas/                  # Base SQL schema and seed data
│   ├── schema.sql            # Core table definitions (DDL)
│   └── seed.sql              # Initial data (13 muscle groups)
├── migrations/               # Sequential SQL migrations (applied in order)
│   ├── 001_add_weekly_snapshots.sql
│   ├── 002_add_abductor_muscle_group.sql
│   ├── 003_add_exercises.sql
│   ├── 003_add_snapshot_exercises.sql
│   └── 004_update_exercises_to_simplified_model.sql
├── prisma/
│   └── schema.prisma         # Prisma schema (introspected from DB)
├── generated/prisma/         # Generated Prisma Client (gitignored)
├── tests/
│   └── smoke.test.ts         # Schema verification smoke tests
├── scripts/                  # Build, deploy, and migration scripts
│   ├── build-docker.sh       # Build Docker image locally
│   ├── migrate-to-do.sh      # Migrate schema to DigitalOcean
│   ├── migrate-to-neon.sh    # Migrate schema to Neon
│   └── grant-permissions.sh  # DB permission management
├── .github/workflows/        # CI/CD pipelines
│   ├── publish-docker.yml    # Build & push image to GHCR
│   ├── migrate-to-do.yml     # Deploy schema to DigitalOcean
│   └── migrate-to-neon.yml   # Deploy schema to Neon
├── test-env/                 # Docker Compose service configs
├── Dockerfile                # postgres:16-alpine based image
├── prisma.config.ts          # Prisma CLI configuration
├── jest.config.js            # Jest test configuration
├── tsconfig.json             # TypeScript configuration
└── package.json              # Node.js project config
```

## Database Details

- **Engine**: PostgreSQL 16 (Alpine)
- **Database**: `xq_fitness`
- **Credentials**: `xq_user` / `xq_password` (local dev)
- **Port**: `5432`
- **Connection String**: `postgresql://xq_user:xq_password@localhost:5432/xq_fitness`

## Schema Architecture

### Tables (9 total)

**Core tables** — Active workout definitions:
- `muscle_groups` — Reference table (13 muscle groups seeded)
- `workout_routines` — Routine definitions with `is_active` flag
- `workout_days` — Days within a routine (unique per `routine_id + day_number`)
- `workout_day_sets` — Sets per muscle group per day (check: `number_of_sets > 0`)
- `exercises` — Individual exercises with reps/weight/sets tracking

**Snapshot tables** — Point-in-time weekly captures:
- `weekly_snapshots` — Weekly snapshot per routine (unique per `routine_id + week_start_date`)
- `snapshot_workout_days` — Captured workout days
- `snapshot_workout_day_sets` — Captured sets configuration
- `snapshot_exercises` — Captured exercise data

### Key Relationships

```
workout_routines ──1:N──> workout_days ──1:N──> workout_day_sets ──N:1──> muscle_groups
                                        └──1:N──> exercises ──────────N:1──> muscle_groups

weekly_snapshots ──1:N──> snapshot_workout_days ──1:N──> snapshot_workout_day_sets ──N:1──> muscle_groups
                                                 └──1:N──> snapshot_exercises ───────N:1──> muscle_groups
```

### Schema Features
- **Cascade deletes** on all foreign keys
- **Auto-updated `updated_at`** via triggers on `workout_routines`, `workout_days`, `workout_day_sets`, `weekly_snapshots`
- **Check constraints** for non-negative values (`total_reps`, `weight`, `total_sets`, `number_of_sets`) and non-empty strings (`exercise_name`)
- **Performance indexes** on foreign keys and commonly queried columns

## Prisma ORM Integration

### Configuration

The Prisma generator is configured for **CJS output with TypeScript**:

```prisma
generator client {
  provider               = "prisma-client"
  output                 = "../generated/prisma"
  moduleFormat           = "cjs"
  generatedFileExtension = "ts"
}
```

- `prisma.config.ts` — Reads `DATABASE_URL` from `.env` via `dotenv/config`
- Generated client is in `generated/prisma/` (gitignored — must run `npx prisma generate`)

### Prisma v7 Usage Pattern

Prisma v7 requires a **driver adapter** — there is no `datasourceUrl` option:

```typescript
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../generated/prisma/client";

const adapter = new PrismaPg({ connectionString: DATABASE_URL });
const prisma = new PrismaClient({ adapter });
```

### Common Prisma Commands

```bash
npx prisma generate          # Regenerate client from schema
npx prisma db pull           # Introspect DB → update schema.prisma
npx prisma studio            # Visual DB browser
```

## Testing

### Stack
- **Jest** — Test runner with `--forceExit` for connection cleanup
- **@swc/jest** — Rust-based TypeScript transform (required for fast compilation of large generated Prisma types)
- **Prisma Client** — Type-safe queries in tests

### Running Tests

```bash
npm run test:smoke    # Run schema smoke tests (31 tests)
npm test              # Run all tests
```

### Smoke Test Coverage (31 tests)
- Database connectivity
- All 9 tables existence
- Per-table: queryability, field structure, relations, constraints, indexes, triggers

### Important: Before running tests
1. Database must be running locally on port 5432
2. Run `npx prisma generate` if `generated/prisma/` is missing

## Docker

### Build & Run Locally

```bash
cd scripts && ./build-docker.sh    # Build xq-fitness-db:latest
./run-docker-local.sh              # Start container on port 5432
```

### How the Docker Image Works

The Dockerfile copies SQL files into `/docker-entrypoint-initdb.d/` in alphabetical order:
1. `01-schema.sql` (base tables)
2. `02-seed.sql` (muscle groups)
3. `03–07` (migrations, sequentially)

PostgreSQL auto-executes these on first container start.

## CI/CD Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `publish-docker.yml` | Push to main, manual | Build & push image to GHCR with git hash + `latest` tag |
| `publish-prisma-client.yml` | Push to main (schema changes), manual | Generate & publish Prisma client to GitHub Packages npm registry |
| `migrate-to-do.yml` | Manual | Apply schema + seed to DigitalOcean managed PostgreSQL |
| `migrate-to-neon.yml` | Manual | Apply schema + seed to Neon serverless PostgreSQL |

## Environment Variables

Managed via `.env` file (gitignored). Required:

```env
DATABASE_URL=postgresql://xq_user:xq_password@localhost:5432/xq_fitness?schema=public
```

For CI/production migrations:
- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`

## Adding a New Migration

1. Create a numbered SQL file in `migrations/` (e.g., `005_description.sql`)
2. Add a `COPY` line in `Dockerfile` to include it in the init sequence
3. Run against local DB to verify
4. Run `npx prisma db pull` to update `schema.prisma`
5. Run `npx prisma generate` to regenerate the client
6. Update smoke tests if new tables/columns were added
7. Commit and push — CI will publish the updated Docker image

## Key Conventions

- **Schema changes** are done via numbered SQL migration files, not Prisma Migrate
- **Prisma** is used for client generation and introspection only (not as the migration tool)
- **Generated code** (`generated/prisma/`) is gitignored — always regenerate after cloning
- **`moduleFormat = "cjs"`** is required for Jest compatibility with Prisma v7
- **`@swc/jest`** is used instead of `ts-jest` because the generated Prisma types are too large for ts-jest