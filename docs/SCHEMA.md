# XQ Fitness Database Schema

Visual reference for the PostgreSQL 16 schema (`xq_fitness`). Source of truth: `schemas/schema.sql` + `migrations/`. Current shape after migration `004_update_exercises_to_simplified_model.sql`.

## High-Level Architecture

Two parallel domains share `muscle_groups` as a reference table:

- **Core** — live workout routine definitions and exercise progress
- **Snapshot** — weekly point-in-time captures of routine state

```mermaid
flowchart TB
    subgraph Core["Core Tables (live data)"]
        WR[workout_routines]
        WD[workout_days]
        WDS[workout_day_sets]
        EX[exercises]
    end

    subgraph Snapshot["Snapshot Tables (historical)"]
        WS[weekly_snapshots]
        SWD[snapshot_workout_days]
        SWDS[snapshot_workout_day_sets]
        SE[snapshot_exercises]
    end

  MG[muscle_groups]

    WR --> WD
    WD --> WDS
    WD --> EX
    MG --> WDS
    MG --> EX

    WR --> WS
    WS --> SWD
    SWD --> SWDS
    SWD --> SE
    MG --> SWDS
    MG --> SE
```

## Core Tables ER Diagram

```mermaid
erDiagram
    muscle_groups {
        serial id PK
        varchar name UK "NOT NULL, UNIQUE"
        text description
        timestamp created_at
    }

    workout_routines {
        serial id PK
        varchar name "NOT NULL"
        text description
        boolean is_active "DEFAULT true"
        timestamp created_at
        timestamp updated_at "trigger"
    }

    workout_days {
        serial id PK
        int routine_id FK "NOT NULL"
        int day_number "NOT NULL"
        varchar day_name "NOT NULL"
        text notes
        timestamp created_at
        timestamp updated_at "trigger"
    }

    workout_day_sets {
        serial id PK
        int workout_day_id FK "NOT NULL"
        int muscle_group_id FK "NOT NULL"
        int number_of_sets "NOT NULL, CHECK > 0"
        text notes
        timestamp created_at
        timestamp updated_at "trigger"
    }

    exercises {
        serial id PK
        int workout_day_id FK "NOT NULL"
        int muscle_group_id FK "NOT NULL"
        varchar exercise_name "NOT NULL"
        int total_reps "DEFAULT 0, CHECK >= 0"
        decimal weight "DEFAULT 0, CHECK >= 0"
        int total_sets "DEFAULT 0, CHECK >= 0"
        text notes
        timestamp created_at
        timestamp updated_at "trigger"
    }

    workout_routines ||--o{ workout_days : "has days"
    workout_days ||--o{ workout_day_sets : "configures sets"
    workout_days ||--o{ exercises : "tracks"
    muscle_groups ||--o{ workout_day_sets : "targeted by"
    muscle_groups ||--o{ exercises : "targeted by"
```

**Unique constraints (core):**

| Table | Constraint | Columns |
|-------|------------|---------|
| `workout_days` | `unique_day_per_routine` | `(routine_id, day_number)` |
| `workout_day_sets` | `unique_muscle_per_day` | `(workout_day_id, muscle_group_id)` |

## Snapshot Tables ER Diagram

Snapshots copy routine state at week boundaries. `original_*` columns store source row IDs **without FK constraints** so historical records survive source deletion.

```mermaid
erDiagram
    workout_routines {
        serial id PK
        varchar name
    }

    weekly_snapshots {
        serial id PK
        int routine_id FK "NOT NULL"
        date week_start_date "NOT NULL (Monday)"
        timestamp created_at
        timestamp updated_at "trigger"
    }

    snapshot_workout_days {
        serial id PK
        int snapshot_id FK "NOT NULL"
        int original_workout_day_id "no FK"
        int day_number "NOT NULL"
        varchar day_name "NOT NULL"
        text notes
        timestamp created_at
    }

    snapshot_workout_day_sets {
        serial id PK
        int snapshot_workout_day_id FK "NOT NULL"
        int original_workout_day_set_id "no FK"
        int muscle_group_id FK "NOT NULL"
        int number_of_sets "NOT NULL, CHECK > 0"
        text notes
        timestamp created_at
    }

    snapshot_exercises {
        serial id PK
        int snapshot_workout_day_id FK "NOT NULL"
        int original_exercise_id "no FK"
        varchar exercise_name "NOT NULL"
        int muscle_group_id FK "NOT NULL"
        int total_reps "DEFAULT 0, CHECK >= 0"
        decimal weight "DEFAULT 0, CHECK >= 0"
        int total_sets "DEFAULT 0, CHECK >= 0"
        text notes
        timestamp created_at
    }

    muscle_groups {
        serial id PK
        varchar name UK
    }

    workout_routines ||--o{ weekly_snapshots : "snapshotted weekly"
    weekly_snapshots ||--o{ snapshot_workout_days : "captures days"
    snapshot_workout_days ||--o{ snapshot_workout_day_sets : "captures set config"
    snapshot_workout_days ||--o{ snapshot_exercises : "captures exercises"
    muscle_groups ||--o{ snapshot_workout_day_sets : "targeted by"
    muscle_groups ||--o{ snapshot_exercises : "targeted by"
```

**Unique constraints (snapshot):**

| Table | Constraint | Columns |
|-------|------------|---------|
| `weekly_snapshots` | `unique_snapshot_per_week` | `(routine_id, week_start_date)` |
| `snapshot_workout_days` | `unique_day_per_snapshot` | `(snapshot_id, day_number)` |
| `snapshot_workout_day_sets` | `unique_muscle_per_snapshot_day` | `(snapshot_workout_day_id, muscle_group_id)` |

## Full Combined ER Diagram

```mermaid
erDiagram
    muscle_groups ||--o{ workout_day_sets : ""
    muscle_groups ||--o{ exercises : ""
    muscle_groups ||--o{ snapshot_workout_day_sets : ""
    muscle_groups ||--o{ snapshot_exercises : ""

    workout_routines ||--o{ workout_days : ""
    workout_routines ||--o{ weekly_snapshots : ""

    workout_days ||--o{ workout_day_sets : ""
    workout_days ||--o{ exercises : ""

    weekly_snapshots ||--o{ snapshot_workout_days : ""
    snapshot_workout_days ||--o{ snapshot_workout_day_sets : ""
    snapshot_workout_days ||--o{ snapshot_exercises : ""
```

## Delete Behavior

```mermaid
flowchart LR
    subgraph CASCADE["ON DELETE CASCADE"]
        A1[workout_routines] --> B1[workout_days]
        A1 --> C1[weekly_snapshots]
        B1 --> D1[workout_day_sets]
        B1 --> E1[exercises]
        C1 --> F1[snapshot_workout_days]
        F1 --> G1[snapshot_workout_day_sets]
        F1 --> H1[snapshot_exercises]
        I1[muscle_groups] --> J1[workout_day_sets]
    end

    subgraph RESTRICT["ON DELETE RESTRICT"]
        K1[muscle_groups] -.-> L1[exercises]
        K1 -.-> M1[snapshot tables]
    end
```

| Parent | Child | ON DELETE |
|--------|-------|-----------|
| `workout_routines` | `workout_days`, `weekly_snapshots` | CASCADE |
| `workout_days` | `workout_day_sets`, `exercises` | CASCADE |
| `muscle_groups` | `workout_day_sets` | CASCADE |
| `muscle_groups` | `exercises`, snapshot muscle FKs | RESTRICT |
| `weekly_snapshots` | `snapshot_workout_days` | CASCADE |
| `snapshot_workout_days` | `snapshot_workout_day_sets`, `snapshot_exercises` | CASCADE |

## Data Flow: Weekly Snapshot

When a weekly snapshot is created (application logic in `write-service`):

1. Read current `workout_days`, `workout_day_sets`, and `exercises` for the routine
2. Insert `weekly_snapshots` row for `(routine_id, week_start_date)`
3. Copy days → `snapshot_workout_days` (store `original_workout_day_id`)
4. Copy set config → `snapshot_workout_day_sets` (store `original_workout_day_set_id`)
5. Copy exercises → `snapshot_exercises` (store `original_exercise_id`)
6. Reset live set counters on the routine

## Reference Data

`muscle_groups` is seeded with 13 rows (12 in `schemas/seed.sql` + Abductor in migration 002).

## Viewing These Diagrams

- **GitHub** — Mermaid renders natively in this file
- **VS Code / Cursor** — use Markdown preview
- **Prisma Studio** — `npx prisma studio` for live data browser (requires running DB)
