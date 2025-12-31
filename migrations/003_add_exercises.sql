-- Migration: Add Exercises Table
-- Description: Adds exercises table for exercise-level progress tracking with sets stored as JSONB
-- Date: 2025-01-27

-- Exercises table
CREATE TABLE IF NOT EXISTS exercises (
    id SERIAL PRIMARY KEY,
    workout_day_id INTEGER NOT NULL REFERENCES workout_days(id) ON DELETE CASCADE,
    muscle_group_id INTEGER NOT NULL REFERENCES muscle_groups(id) ON DELETE RESTRICT,
    exercise_name VARCHAR(200) NOT NULL,
    sets JSONB NOT NULL DEFAULT '[]'::jsonb,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT exercise_name_not_empty CHECK (LENGTH(TRIM(exercise_name)) > 0)
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_exercises_workout_day ON exercises(workout_day_id);
CREATE INDEX IF NOT EXISTS idx_exercises_muscle_group ON exercises(muscle_group_id);
CREATE INDEX IF NOT EXISTS idx_exercises_workout_day_muscle_group ON exercises(workout_day_id, muscle_group_id);
CREATE INDEX IF NOT EXISTS idx_exercises_sets_gin ON exercises USING GIN (sets);

-- Apply updated_at trigger for exercises
DROP TRIGGER IF EXISTS update_exercises_updated_at ON exercises;
CREATE TRIGGER update_exercises_updated_at BEFORE UPDATE ON exercises
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

