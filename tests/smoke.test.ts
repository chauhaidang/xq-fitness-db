import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../generated/prisma/client";

const DATABASE_URL =
    process.env.DATABASE_URL ||
    "postgresql://xq_user:xq_password@localhost:5432/xq_fitness?schema=public";

const adapter = new PrismaPg({ connectionString: DATABASE_URL });
const prisma = new PrismaClient({ adapter });

afterAll(async () => {
    await prisma.$disconnect();
});

// ─── Connectivity ──────────────────────────────────────────────────

describe("Database connectivity", () => {
    it("should connect to xq_fitness database", async () => {
        const result: [{ current_database: string }] =
            await prisma.$queryRaw`SELECT current_database()`;
        expect(result[0].current_database).toBe("xq_fitness");
    });
});

// ─── Table existence ───────────────────────────────────────────────

describe("Table existence", () => {
    it("should have all expected tables", async () => {
        const tables: { table_name: string }[] = await prisma.$queryRaw`
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
      ORDER BY table_name
    `;
        const tableNames = tables.map((t) => t.table_name);

        const expectedTables = [
            "exercises",
            "muscle_groups",
            "snapshot_exercises",
            "snapshot_workout_day_sets",
            "snapshot_workout_days",
            "weekly_snapshots",
            "workout_day_sets",
            "workout_days",
            "workout_routines",
        ];
        for (const table of expectedTables) {
            expect(tableNames).toContain(table);
        }
    });
});

// ─── muscle_groups ─────────────────────────────────────────────────

describe("muscle_groups table", () => {
    it("should be queryable and have correct field structure", async () => {
        const records = await prisma.muscle_groups.findMany({ take: 1 });
        expect(Array.isArray(records)).toBe(true);
        if (records.length > 0) {
            expect(records[0]).toHaveProperty("id");
            expect(records[0]).toHaveProperty("name");
            expect(records[0]).toHaveProperty("description");
            expect(records[0]).toHaveProperty("created_at");
        }
    });

    it("should have unique constraint on name", async () => {
        const constraints: { constraint_name: string; column_name: string }[] =
            await prisma.$queryRaw`
        SELECT kcu.constraint_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_schema = 'public'
          AND tc.table_name = 'muscle_groups'
          AND tc.constraint_type = 'UNIQUE'
      `;
        const nameUnique = constraints.find((c) => c.column_name === "name");
        expect(nameUnique).toBeDefined();
    });
});

// ─── workout_routines ──────────────────────────────────────────────

describe("workout_routines table", () => {
    it("should be queryable with correct fields", async () => {
        const records = await prisma.workout_routines.findMany({ take: 1 });
        expect(Array.isArray(records)).toBe(true);
        if (records.length > 0) {
            expect(records[0]).toHaveProperty("id");
            expect(records[0]).toHaveProperty("name");
            expect(records[0]).toHaveProperty("description");
            expect(records[0]).toHaveProperty("is_active");
            expect(records[0]).toHaveProperty("created_at");
            expect(records[0]).toHaveProperty("updated_at");
        }
    });

    it("should have index on is_active", async () => {
        const indexes: { indexname: string }[] = await prisma.$queryRaw`
      SELECT indexname FROM pg_indexes
      WHERE schemaname = 'public' AND tablename = 'workout_routines'
    `;
        const indexNames = indexes.map((i) => i.indexname);
        expect(indexNames).toContain("idx_routines_active");
    });

    it("should have update trigger", async () => {
        const triggers: { trigger_name: string; event_manipulation: string }[] =
            await prisma.$queryRaw`
        SELECT trigger_name, event_manipulation
        FROM information_schema.triggers
        WHERE event_object_schema = 'public'
          AND event_object_table = 'workout_routines'
      `;
        const updateTrigger = triggers.find(
            (t) => t.trigger_name === "update_workout_routines_updated_at"
        );
        expect(updateTrigger).toBeDefined();
        expect(updateTrigger!.event_manipulation).toBe("UPDATE");
    });
});

// ─── workout_days ──────────────────────────────────────────────────

describe("workout_days table", () => {
    it("should be queryable with correct fields", async () => {
        const records = await prisma.workout_days.findMany({ take: 1 });
        expect(Array.isArray(records)).toBe(true);
        if (records.length > 0) {
            expect(records[0]).toHaveProperty("id");
            expect(records[0]).toHaveProperty("routine_id");
            expect(records[0]).toHaveProperty("day_number");
            expect(records[0]).toHaveProperty("day_name");
        }
    });

    it("should support relation to workout_routines", async () => {
        const record = await prisma.workout_days.findFirst({
            include: { workout_routines: true },
        });
        if (record) {
            expect(record).toHaveProperty("workout_routines");
            expect(record.workout_routines).toHaveProperty("id");
        }
    });

    it("should have unique constraint on (routine_id, day_number)", async () => {
        const constraints: { constraint_name: string; column_name: string }[] =
            await prisma.$queryRaw`
        SELECT kcu.constraint_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_schema = 'public'
          AND tc.table_name = 'workout_days'
          AND tc.constraint_type = 'UNIQUE'
        ORDER BY kcu.constraint_name, kcu.ordinal_position
      `;
        const constraint = constraints.filter(
            (c) => c.constraint_name === "unique_day_per_routine"
        );
        const colNames = constraint.map((c) => c.column_name).sort();
        expect(colNames).toEqual(["day_number", "routine_id"]);
    });
});

// ─── workout_day_sets ──────────────────────────────────────────────

describe("workout_day_sets table", () => {
    it("should be queryable with correct fields", async () => {
        const records = await prisma.workout_day_sets.findMany({ take: 1 });
        expect(Array.isArray(records)).toBe(true);
        if (records.length > 0) {
            expect(records[0]).toHaveProperty("id");
            expect(records[0]).toHaveProperty("workout_day_id");
            expect(records[0]).toHaveProperty("muscle_group_id");
            expect(records[0]).toHaveProperty("number_of_sets");
        }
    });

    it("should support relations to workout_days and muscle_groups", async () => {
        const record = await prisma.workout_day_sets.findFirst({
            include: { workout_days: true, muscle_groups: true },
        });
        if (record) {
            expect(record).toHaveProperty("workout_days");
            expect(record).toHaveProperty("muscle_groups");
        }
    });

    it("should have unique constraint on (workout_day_id, muscle_group_id)", async () => {
        const constraints: { constraint_name: string; column_name: string }[] =
            await prisma.$queryRaw`
        SELECT kcu.constraint_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_schema = 'public'
          AND tc.table_name = 'workout_day_sets'
          AND tc.constraint_type = 'UNIQUE'
        ORDER BY kcu.constraint_name, kcu.ordinal_position
      `;
        const constraint = constraints.filter(
            (c) => c.constraint_name === "unique_muscle_per_day"
        );
        const colNames = constraint.map((c) => c.column_name).sort();
        expect(colNames).toEqual(["muscle_group_id", "workout_day_id"]);
    });

    it("should have check constraint on number_of_sets > 0", async () => {
        const checks: { constraint_name: string }[] = await prisma.$queryRaw`
      SELECT cc.constraint_name
      FROM information_schema.check_constraints cc
      JOIN information_schema.table_constraints tc
        ON cc.constraint_name = tc.constraint_name
      WHERE tc.table_schema = 'public'
        AND tc.table_name = 'workout_day_sets'
        AND cc.constraint_name LIKE '%number_of_sets%'
    `;
        expect(checks.length).toBeGreaterThan(0);
    });
});

// ─── exercises ─────────────────────────────────────────────────────

describe("exercises table", () => {
    it("should be queryable with correct fields", async () => {
        const records = await prisma.exercises.findMany({ take: 1 });
        expect(Array.isArray(records)).toBe(true);
        if (records.length > 0) {
            expect(records[0]).toHaveProperty("id");
            expect(records[0]).toHaveProperty("workout_day_id");
            expect(records[0]).toHaveProperty("muscle_group_id");
            expect(records[0]).toHaveProperty("exercise_name");
            expect(records[0]).toHaveProperty("total_reps");
            expect(records[0]).toHaveProperty("weight");
            expect(records[0]).toHaveProperty("total_sets");
        }
    });

    it("should support relations to workout_days and muscle_groups", async () => {
        const record = await prisma.exercises.findFirst({
            include: { workout_days: true, muscle_groups: true },
        });
        if (record) {
            expect(record).toHaveProperty("workout_days");
            expect(record).toHaveProperty("muscle_groups");
        }
    });

    it("should have check constraint on exercise_name not empty", async () => {
        const checks: { constraint_name: string }[] = await prisma.$queryRaw`
      SELECT cc.constraint_name
      FROM information_schema.check_constraints cc
      JOIN information_schema.table_constraints tc
        ON cc.constraint_name = tc.constraint_name
      WHERE tc.table_schema = 'public'
        AND tc.table_name = 'exercises'
        AND cc.constraint_name = 'exercise_name_not_empty'
    `;
        expect(checks.length).toBe(1);
    });

    it("should have check constraints for non-negative values", async () => {
        const checks: { constraint_name: string }[] = await prisma.$queryRaw`
      SELECT cc.constraint_name
      FROM information_schema.check_constraints cc
      JOIN information_schema.table_constraints tc
        ON cc.constraint_name = tc.constraint_name
      WHERE tc.table_schema = 'public'
        AND tc.table_name = 'exercises'
        AND cc.constraint_name NOT LIKE '%_not_null'
      ORDER BY cc.constraint_name
    `;
        const checkNames = checks.map((c) => c.constraint_name);
        expect(checkNames).toContain("exercises_total_reps_non_negative");
        expect(checkNames).toContain("exercises_weight_non_negative");
        expect(checkNames).toContain("exercises_total_sets_non_negative");
    });

    it("should have performance indexes", async () => {
        const indexes: { indexname: string }[] = await prisma.$queryRaw`
      SELECT indexname FROM pg_indexes
      WHERE schemaname = 'public' AND tablename = 'exercises'
    `;
        const indexNames = indexes.map((i) => i.indexname);
        expect(indexNames).toContain("idx_exercises_muscle_group");
        expect(indexNames).toContain("idx_exercises_workout_day");
        expect(indexNames).toContain("idx_exercises_workout_day_muscle_group");
    });
});

// ─── weekly_snapshots ──────────────────────────────────────────────

describe("weekly_snapshots table", () => {
    it("should be queryable with correct fields", async () => {
        const records = await prisma.weekly_snapshots.findMany({ take: 1 });
        expect(Array.isArray(records)).toBe(true);
        if (records.length > 0) {
            expect(records[0]).toHaveProperty("id");
            expect(records[0]).toHaveProperty("routine_id");
            expect(records[0]).toHaveProperty("week_start_date");
            expect(records[0]).toHaveProperty("created_at");
            expect(records[0]).toHaveProperty("updated_at");
        }
    });

    it("should support relation to workout_routines", async () => {
        const record = await prisma.weekly_snapshots.findFirst({
            include: { workout_routines: true },
        });
        if (record) {
            expect(record).toHaveProperty("workout_routines");
        }
    });

    it("should have unique constraint on (routine_id, week_start_date)", async () => {
        const constraints: { constraint_name: string; column_name: string }[] =
            await prisma.$queryRaw`
        SELECT kcu.constraint_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_schema = 'public'
          AND tc.table_name = 'weekly_snapshots'
          AND tc.constraint_type = 'UNIQUE'
        ORDER BY kcu.constraint_name, kcu.ordinal_position
      `;
        const constraint = constraints.filter(
            (c) => c.constraint_name === "unique_snapshot_per_week"
        );
        const colNames = constraint.map((c) => c.column_name).sort();
        expect(colNames).toEqual(["routine_id", "week_start_date"]);
    });
});

// ─── snapshot_workout_days ─────────────────────────────────────────

describe("snapshot_workout_days table", () => {
    it("should be queryable with correct fields", async () => {
        const records = await prisma.snapshot_workout_days.findMany({ take: 1 });
        expect(Array.isArray(records)).toBe(true);
        if (records.length > 0) {
            expect(records[0]).toHaveProperty("id");
            expect(records[0]).toHaveProperty("snapshot_id");
            expect(records[0]).toHaveProperty("original_workout_day_id");
            expect(records[0]).toHaveProperty("day_number");
            expect(records[0]).toHaveProperty("day_name");
        }
    });

    it("should support relation to weekly_snapshots", async () => {
        const record = await prisma.snapshot_workout_days.findFirst({
            include: { weekly_snapshots: true },
        });
        if (record) {
            expect(record).toHaveProperty("weekly_snapshots");
        }
    });

    it("should have unique constraint on (snapshot_id, day_number)", async () => {
        const constraints: { constraint_name: string; column_name: string }[] =
            await prisma.$queryRaw`
        SELECT kcu.constraint_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_schema = 'public'
          AND tc.table_name = 'snapshot_workout_days'
          AND tc.constraint_type = 'UNIQUE'
        ORDER BY kcu.constraint_name, kcu.ordinal_position
      `;
        const constraint = constraints.filter(
            (c) => c.constraint_name === "unique_day_per_snapshot"
        );
        const colNames = constraint.map((c) => c.column_name).sort();
        expect(colNames).toEqual(["day_number", "snapshot_id"]);
    });
});

// ─── snapshot_workout_day_sets ──────────────────────────────────────

describe("snapshot_workout_day_sets table", () => {
    it("should be queryable with correct fields", async () => {
        const records = await prisma.snapshot_workout_day_sets.findMany({
            take: 1,
        });
        expect(Array.isArray(records)).toBe(true);
        if (records.length > 0) {
            expect(records[0]).toHaveProperty("id");
            expect(records[0]).toHaveProperty("snapshot_workout_day_id");
            expect(records[0]).toHaveProperty("original_workout_day_set_id");
            expect(records[0]).toHaveProperty("muscle_group_id");
            expect(records[0]).toHaveProperty("number_of_sets");
        }
    });

    it("should support relations", async () => {
        const record = await prisma.snapshot_workout_day_sets.findFirst({
            include: {
                snapshot_workout_days: true,
                muscle_groups: true,
            },
        });
        if (record) {
            expect(record).toHaveProperty("snapshot_workout_days");
            expect(record).toHaveProperty("muscle_groups");
        }
    });

    it("should have unique constraint on (snapshot_workout_day_id, muscle_group_id)", async () => {
        const constraints: { constraint_name: string; column_name: string }[] =
            await prisma.$queryRaw`
        SELECT kcu.constraint_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_schema = 'public'
          AND tc.table_name = 'snapshot_workout_day_sets'
          AND tc.constraint_type = 'UNIQUE'
        ORDER BY kcu.constraint_name, kcu.ordinal_position
      `;
        const constraint = constraints.filter(
            (c) => c.constraint_name === "unique_muscle_per_snapshot_day"
        );
        const colNames = constraint.map((c) => c.column_name).sort();
        expect(colNames).toEqual([
            "muscle_group_id",
            "snapshot_workout_day_id",
        ]);
    });
});

// ─── snapshot_exercises ────────────────────────────────────────────

describe("snapshot_exercises table", () => {
    it("should be queryable with correct fields", async () => {
        const records = await prisma.snapshot_exercises.findMany({ take: 1 });
        expect(Array.isArray(records)).toBe(true);
        if (records.length > 0) {
            expect(records[0]).toHaveProperty("id");
            expect(records[0]).toHaveProperty("snapshot_workout_day_id");
            expect(records[0]).toHaveProperty("original_exercise_id");
            expect(records[0]).toHaveProperty("exercise_name");
            expect(records[0]).toHaveProperty("muscle_group_id");
            expect(records[0]).toHaveProperty("total_reps");
            expect(records[0]).toHaveProperty("weight");
            expect(records[0]).toHaveProperty("total_sets");
        }
    });

    it("should support relations", async () => {
        const record = await prisma.snapshot_exercises.findFirst({
            include: {
                snapshot_workout_days: true,
                muscle_groups: true,
            },
        });
        if (record) {
            expect(record).toHaveProperty("snapshot_workout_days");
            expect(record).toHaveProperty("muscle_groups");
        }
    });

    it("should have check constraints for non-negative values", async () => {
        const checks: { constraint_name: string }[] = await prisma.$queryRaw`
      SELECT cc.constraint_name
      FROM information_schema.check_constraints cc
      JOIN information_schema.table_constraints tc
        ON cc.constraint_name = tc.constraint_name
      WHERE tc.table_schema = 'public'
        AND tc.table_name = 'snapshot_exercises'
        AND cc.constraint_name NOT LIKE '%_not_null'
      ORDER BY cc.constraint_name
    `;
        const checkNames = checks.map((c) => c.constraint_name);
        expect(checkNames).toContain(
            "snapshot_exercises_total_reps_non_negative"
        );
        expect(checkNames).toContain("snapshot_exercises_weight_non_negative");
        expect(checkNames).toContain(
            "snapshot_exercises_total_sets_non_negative"
        );
    });
});
