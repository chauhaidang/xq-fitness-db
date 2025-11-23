-- Seed data for muscle groups

INSERT INTO muscle_groups (name, description) VALUES
    ('Chest', 'Pectoralis major and minor muscles'),
    ('Back', 'Latissimus dorsi, trapezius, and rhomboids'),
    ('Shoulders', 'Deltoids (anterior, lateral, posterior)'),
    ('Biceps', 'Biceps brachii'),
    ('Triceps', 'Triceps brachii'),
    ('Forearms', 'Wrist flexors and extensors'),
    ('Quadriceps', 'Front thigh muscles'),
    ('Hamstrings', 'Back thigh muscles'),
    ('Glutes', 'Gluteus maximus, medius, and minimus'),
    ('Calves', 'Gastrocnemius and soleus'),
    ('Abs', 'Rectus abdominis and obliques'),
    ('Lower Back', 'Erector spinae')
ON CONFLICT (name) DO NOTHING;
