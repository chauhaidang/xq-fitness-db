-- Migration: Add Abductor Muscle Group
-- Description: Adds Abductor muscle group (ID: 13) to the muscle_groups table
-- Date: 2025-12-23

INSERT INTO muscle_groups (name, description) VALUES
    ('Abductor', 'Hip abductor muscles (gluteus medius, gluteus minimus, tensor fasciae latae)')
ON CONFLICT (name) DO NOTHING;

