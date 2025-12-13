-- Migration: Add Weekly Snapshot Tables
-- Description: Adds tables for weekly routine snapshots and snapshot workout data
-- Date: 2024-12-07

-- Weekly snapshots table
CREATE TABLE IF NOT EXISTS weekly_snapshots (
    id SERIAL PRIMARY KEY,
    routine_id INTEGER NOT NULL REFERENCES workout_routines(id) ON DELETE CASCADE,
    week_start_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT unique_snapshot_per_week UNIQUE(routine_id, week_start_date)
);

-- Snapshot workout days table
CREATE TABLE IF NOT EXISTS snapshot_workout_days (
    id SERIAL PRIMARY KEY,
    snapshot_id INTEGER NOT NULL REFERENCES weekly_snapshots(id) ON DELETE CASCADE,
    original_workout_day_id INTEGER NOT NULL,
    day_number INTEGER NOT NULL,
    day_name VARCHAR(100) NOT NULL,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT unique_day_per_snapshot UNIQUE(snapshot_id, day_number)
);

-- Snapshot workout day sets table
CREATE TABLE IF NOT EXISTS snapshot_workout_day_sets (
    id SERIAL PRIMARY KEY,
    snapshot_workout_day_id INTEGER NOT NULL REFERENCES snapshot_workout_days(id) ON DELETE CASCADE,
    original_workout_day_set_id INTEGER NOT NULL,
    muscle_group_id INTEGER NOT NULL REFERENCES muscle_groups(id) ON DELETE RESTRICT,
    number_of_sets INTEGER NOT NULL CHECK (number_of_sets > 0),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT unique_muscle_per_snapshot_day UNIQUE(snapshot_workout_day_id, muscle_group_id)
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_weekly_snapshots_routine ON weekly_snapshots(routine_id);
CREATE INDEX IF NOT EXISTS idx_weekly_snapshots_week_start ON weekly_snapshots(week_start_date);
CREATE INDEX IF NOT EXISTS idx_snapshot_workout_days_snapshot ON snapshot_workout_days(snapshot_id);
CREATE INDEX IF NOT EXISTS idx_snapshot_workout_day_sets_day ON snapshot_workout_day_sets(snapshot_workout_day_id);
CREATE INDEX IF NOT EXISTS idx_snapshot_workout_day_sets_muscle ON snapshot_workout_day_sets(muscle_group_id);

-- Updated_at trigger function (reuse existing if present, otherwise create)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers for weekly_snapshots
DROP TRIGGER IF EXISTS update_weekly_snapshots_updated_at ON weekly_snapshots;
CREATE TRIGGER update_weekly_snapshots_updated_at BEFORE UPDATE ON weekly_snapshots
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
