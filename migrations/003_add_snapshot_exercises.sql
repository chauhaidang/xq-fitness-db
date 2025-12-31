-- Migration: Add Snapshot Exercises Table
-- Description: Adds snapshot_exercises table for capturing exercise data in weekly snapshots with sets stored as JSONB
-- Date: 2025-01-27

-- Snapshot exercises table
CREATE TABLE IF NOT EXISTS snapshot_exercises (
    id SERIAL PRIMARY KEY,
    snapshot_workout_day_id INTEGER NOT NULL REFERENCES snapshot_workout_days(id) ON DELETE CASCADE,
    original_exercise_id INTEGER NOT NULL,
    exercise_name VARCHAR(200) NOT NULL,
    muscle_group_id INTEGER NOT NULL REFERENCES muscle_groups(id) ON DELETE RESTRICT,
    sets JSONB NOT NULL DEFAULT '[]'::jsonb,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_snapshot_exercises_snapshot_workout_day ON snapshot_exercises(snapshot_workout_day_id);
CREATE INDEX IF NOT EXISTS idx_snapshot_exercises_muscle_group ON snapshot_exercises(muscle_group_id);
CREATE INDEX IF NOT EXISTS idx_snapshot_exercises_sets_gin ON snapshot_exercises USING GIN (sets);

