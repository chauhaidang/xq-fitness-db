---
name: database-prisma
description: Working with PostgreSQL database design, schema migrations, Prisma v7 ORM, and database smoke testing in the xq-fitness project.
---

# Database & Prisma Skill

Use this skill when working with database schema design, PostgreSQL migrations, Prisma ORM client generation, or database smoke testing.

## Prerequisites

- Docker running locally (for database container)
- Node.js installed
- Database container running on port 5432

### Quick Start — Spin Up Local Database

```bash
cd scripts && ./build-docker.sh && ./run-docker-local.sh
```

Or connect to an existing PostgreSQL instance and set `DATABASE_URL` in `.env`.

---

## 1. Schema Design (PostgreSQL)

### Conventions

- All tables use `SERIAL PRIMARY KEY` for `id` columns
- Timestamps use `TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP`
- Tables with mutable data get an `updated_at` column with an auto-update trigger
- Foreign keys use `ON DELETE CASCADE`
- Use named constraints for readability and testability (e.g., `exercise_name_not_empty`, `exercises_total_reps_non_negative`)
- Use composite unique constraints for natural keys (e.g., `unique_day_per_routine`)

### Creating a Trigger for `updated_at`

```sql
-- Create the trigger function (once per database)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach to a table
CREATE TRIGGER update_<table_name>_updated_at
    BEFORE UPDATE ON <table_name>
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

### Index Naming Convention

```
idx_<table>_<column>                    -- Single column
idx_<table>_<col1>_<col2>              -- Composite
```

### Check Constraint Pattern

```sql
CONSTRAINT <table>_<column>_non_negative CHECK (<column> >= 0)
CONSTRAINT <column>_not_empty CHECK (TRIM(<column>) <> '')
```

---

## 2. SQL Migrations

Schema changes are managed via **numbered SQL files**, not Prisma Migrate.

### Adding a New Migration

1. **Create the migration file**:
   ```bash
   touch migrations/005_description.sql
   ```

2. **Write idempotent SQL** when possible:
   ```sql
   -- migrations/005_add_new_table.sql
   CREATE TABLE IF NOT EXISTS new_table (
       id SERIAL PRIMARY KEY,
       name VARCHAR(200) NOT NULL,
       created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
   );
   ```

3. **Add to Dockerfile** (maintains execution order):
   ```dockerfile
   COPY migrations/005_add_new_table.sql /docker-entrypoint-initdb.d/08-add_new_table.sql
   ```

4. **Apply to local database** to verify:
   ```bash
   psql postgresql://xq_user:xq_password@localhost:5432/xq_fitness -f migrations/005_add_new_table.sql
   ```

5. **Sync Prisma schema**:
   ```bash
   npx prisma db pull       # Introspect DB → update schema.prisma
   npx prisma generate      # Regenerate TypeScript client
   ```

6. **Update smoke tests** in `tests/smoke.test.ts` if new tables/columns were added.

7. **Rebuild Docker image**:
   ```bash
   cd scripts && ./build-docker.sh
   ```

---

## 3. Prisma v7 ORM

### Key Configuration

The project uses Prisma v7 with the `prisma-client` generator (not the deprecated `prisma-client-js`).

**Schema** (`prisma/schema.prisma`):
```prisma
generator client {
  provider               = "prisma-client"
  output                 = "../generated/prisma"
  moduleFormat           = "cjs"
  generatedFileExtension = "ts"
}
```

**Config** (`prisma.config.ts`):
```typescript
import "dotenv/config";
import { defineConfig } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  datasource: { url: process.env["DATABASE_URL"] },
});
```

### Important: Prisma v7 Breaking Changes

1. **Driver adapters are mandatory** — No more `datasourceUrl` in `PrismaClient` constructor
2. **`moduleFormat = "cjs"`** is required for Jest compatibility (ESM generates `import.meta.url` which breaks Jest)
3. **Generated code is TypeScript** (`generatedFileExtension = "ts"`) — provides full type safety

### Instantiating PrismaClient

```typescript
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../generated/prisma/client";

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL! });
const prisma = new PrismaClient({ adapter });
```

> **IMPORTANT**: `PrismaPg` takes `{ connectionString }`, NOT a `pg.Pool` instance.

### Common Operations

```typescript
// Find many
const groups = await prisma.muscle_groups.findMany();

// Find with relations
const day = await prisma.workout_days.findFirst({
  include: { workout_routines: true, exercises: true },
});

// Raw SQL (for schema introspection, complex queries)
const tables = await prisma.$queryRaw`
  SELECT table_name FROM information_schema.tables
  WHERE table_schema = 'public'
`;

// Disconnect
await prisma.$disconnect();
```

### Regenerating After Schema Changes

```bash
npx prisma db pull       # Pull DB schema → schema.prisma
npx prisma generate      # Generate TypeScript client
```

---

## 4. Testing

### Stack

| Tool | Purpose |
|------|---------|
| Jest | Test runner (`--forceExit` for connection cleanup) |
| @swc/jest | Rust-based TS transform (fast compilation of large Prisma types) |
| Prisma Client | Type-safe database queries in tests |

> **Why @swc/jest?** The generated Prisma types are very large (~50KB+ in `prismaNamespace.ts`). `ts-jest` hangs when compiling them. `@swc/jest` processes them in under a second.

### Running Tests

```bash
npm run test:smoke    # Schema verification (31 tests)
npm test              # All tests
```

### Writing a Smoke Test for a New Table

```typescript
describe("new_table table", () => {
  // 1. Queryability + field structure
  it("should be queryable with correct fields", async () => {
    const records = await prisma.new_table.findMany({ take: 1 });
    expect(Array.isArray(records)).toBe(true);
    if (records.length > 0) {
      expect(records[0]).toHaveProperty("id");
      expect(records[0]).toHaveProperty("name");
    }
  });

  // 2. Relations (if any)
  it("should support relation to parent_table", async () => {
    const record = await prisma.new_table.findFirst({
      include: { parent_table: true },
    });
    if (record) {
      expect(record).toHaveProperty("parent_table");
    }
  });

  // 3. Constraints (unique, check)
  it("should have unique constraint on name", async () => {
    const constraints = await prisma.$queryRaw`
      SELECT kcu.constraint_name, kcu.column_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
      WHERE tc.table_schema = 'public'
        AND tc.table_name = 'new_table'
        AND tc.constraint_type = 'UNIQUE'
    `;
    // Assert constraint exists
  });

  // 4. Indexes
  it("should have performance indexes", async () => {
    const indexes = await prisma.$queryRaw`
      SELECT indexname FROM pg_indexes
      WHERE schemaname = 'public' AND tablename = 'new_table'
    `;
    // Assert index exists
  });
});
```

### Test Pattern Summary

| What to verify | Method |
|---|---|
| Table queryability | `prisma.model.findMany({ take: 1 })` |
| Field structure | `toHaveProperty()` on returned records |
| Relations | `prisma.model.findFirst({ include: { ... } })` |
| Unique constraints | `$queryRaw` → `information_schema.table_constraints` |
| Check constraints | `$queryRaw` → `information_schema.check_constraints` |
| Indexes | `$queryRaw` → `pg_indexes` |
| Triggers | `$queryRaw` → `information_schema.triggers` |

---

## 5. Troubleshooting

### "Cannot find module '../generated/prisma/client'"
Run `npx prisma generate` — the generated directory is gitignored.

### Jest hangs indefinitely
- Ensure using `@swc/jest` (not `ts-jest`) in `jest.config.js`
- Ensure `moduleFormat = "cjs"` in `schema.prisma`
- Use `--forceExit` flag in test scripts

### "PrismaClient constructor error"
Prisma v7 requires a driver adapter. Use:
```typescript
const adapter = new PrismaPg({ connectionString: DATABASE_URL });
const prisma = new PrismaClient({ adapter });
```

### Connection refused
Database container is not running. Start it:
```bash
cd scripts && ./build-docker.sh && ./run-docker-local.sh
```
