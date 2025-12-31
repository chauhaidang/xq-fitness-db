# XQ Fitness Database Container
FROM postgres:16-alpine

# Set environment variables for database configuration
ENV POSTGRES_DB=xq_fitness
ENV POSTGRES_USER=xq_user
ENV POSTGRES_PASSWORD=xq_password

# Copy initialization scripts
# PostgreSQL will run scripts in /docker-entrypoint-initdb.d/ in alphabetical order
COPY schemas/schema.sql /docker-entrypoint-initdb.d/01-schema.sql
COPY schemas/seed.sql /docker-entrypoint-initdb.d/02-seed.sql
COPY migrations/001_add_weekly_snapshots.sql /docker-entrypoint-initdb.d/03-add_weekly_snapshots.sql
COPY migrations/002_add_abductor_muscle_group.sql /docker-entrypoint-initdb.d/04-add_abductor_muscle_group.sql
COPY migrations/003_add_exercises.sql /docker-entrypoint-initdb.d/05-add_exercises.sql
COPY migrations/003_add_snapshot_exercises.sql /docker-entrypoint-initdb.d/06-add_snapshot_exercises.sql

# Expose PostgreSQL port
EXPOSE 5432

# Health check to ensure database is ready
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB} || exit 1

# Default command (inherited from base image)
# CMD ["postgres"]
