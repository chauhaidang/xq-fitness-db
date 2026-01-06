-- Migration: Update Exercises to Simplified Model
-- Description: Alters existing exercises and snapshot_exercises tables to use direct columns (total_reps, weight, total_sets) instead of JSONB sets array
-- Date: 2025-01-27
-- Note: This migration updates tables created by 003_add_exercises.sql and 003_add_snapshot_exercises.sql

-- ============================================
-- Update exercises table
-- ============================================

-- Add new columns to exercises table
ALTER TABLE exercises
    ADD COLUMN IF NOT EXISTS total_reps INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS weight DECIMAL(10,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_sets INTEGER NOT NULL DEFAULT 0;

-- Drop GIN index on sets JSONB column (no longer needed)
DROP INDEX IF EXISTS idx_exercises_sets_gin;

-- Drop sets JSONB column
ALTER TABLE exercises
    DROP COLUMN IF EXISTS sets;

-- Add check constraints for new columns (drop first to make idempotent)
ALTER TABLE exercises
    DROP CONSTRAINT IF EXISTS exercises_total_reps_non_negative,
    DROP CONSTRAINT IF EXISTS exercises_weight_non_negative,
    DROP CONSTRAINT IF EXISTS exercises_total_sets_non_negative;

ALTER TABLE exercises
    ADD CONSTRAINT exercises_total_reps_non_negative CHECK (total_reps >= 0),
    ADD CONSTRAINT exercises_weight_non_negative CHECK (weight >= 0),
    ADD CONSTRAINT exercises_total_sets_non_negative CHECK (total_sets >= 0);

-- Indexes for exercises table
CREATE INDEX IF NOT EXISTS idx_exercises_workout_day ON exercises(workout_day_id);
CREATE INDEX IF NOT EXISTS idx_exercises_muscle_group ON exercises(muscle_group_id);
CREATE INDEX IF NOT EXISTS idx_exercises_workout_day_muscle_group ON exercises(workout_day_id, muscle_group_id);

-- ============================================
-- Update snapshot_exercises table
-- ============================================

-- Add new columns to snapshot_exercises table
ALTER TABLE snapshot_exercises
    ADD COLUMN IF NOT EXISTS total_reps INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS weight DECIMAL(10,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_sets INTEGER NOT NULL DEFAULT 0;

-- Drop GIN index on sets JSONB column (no longer needed)
DROP INDEX IF EXISTS idx_snapshot_exercises_sets_gin;

-- Drop sets JSONB column
ALTER TABLE snapshot_exercises
    DROP COLUMN IF EXISTS sets;

-- Add check constraints for new columns (drop first to make idempotent)
ALTER TABLE snapshot_exercises
    DROP CONSTRAINT IF EXISTS snapshot_exercises_total_reps_non_negative,
    DROP CONSTRAINT IF EXISTS snapshot_exercises_weight_non_negative,
    DROP CONSTRAINT IF EXISTS snapshot_exercises_total_sets_non_negative;

ALTER TABLE snapshot_exercises
    ADD CONSTRAINT snapshot_exercises_total_reps_non_negative CHECK (total_reps >= 0),
    ADD CONSTRAINT snapshot_exercises_weight_non_negative CHECK (weight >= 0),
    ADD CONSTRAINT snapshot_exercises_total_sets_non_negative CHECK (total_sets >= 0);

