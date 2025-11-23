-- XQ Fitness Database Schema

-- Muscle groups reference table
CREATE TABLE IF NOT EXISTS muscle_groups (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Workout routines
CREATE TABLE IF NOT EXISTS workout_routines (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Workout days within a routine
CREATE TABLE IF NOT EXISTS workout_days (
    id SERIAL PRIMARY KEY,
    routine_id INTEGER NOT NULL REFERENCES workout_routines(id) ON DELETE CASCADE,
    day_number INTEGER NOT NULL,
    day_name VARCHAR(100) NOT NULL,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_day_per_routine UNIQUE(routine_id, day_number)
);

-- Sets configuration for each muscle group on a workout day
CREATE TABLE IF NOT EXISTS workout_day_sets (
    id SERIAL PRIMARY KEY,
    workout_day_id INTEGER NOT NULL REFERENCES workout_days(id) ON DELETE CASCADE,
    muscle_group_id INTEGER NOT NULL REFERENCES muscle_groups(id) ON DELETE CASCADE,
    number_of_sets INTEGER NOT NULL CHECK (number_of_sets > 0),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_muscle_per_day UNIQUE(workout_day_id, muscle_group_id)
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_workout_days_routine ON workout_days(routine_id);
CREATE INDEX IF NOT EXISTS idx_workout_day_sets_day ON workout_day_sets(workout_day_id);
CREATE INDEX IF NOT EXISTS idx_workout_day_sets_muscle ON workout_day_sets(muscle_group_id);
CREATE INDEX IF NOT EXISTS idx_routines_active ON workout_routines(is_active);

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers
CREATE TRIGGER update_workout_routines_updated_at BEFORE UPDATE ON workout_routines
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_workout_days_updated_at BEFORE UPDATE ON workout_days
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_workout_day_sets_updated_at BEFORE UPDATE ON workout_day_sets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
