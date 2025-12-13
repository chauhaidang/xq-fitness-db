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

# Copy and execute migration files
# PostgreSQL will execute .sql files in /docker-entrypoint-initdb.d/ in alphabetical order
# Copy migrations with 03- prefix to run after schema (01) and seed (02)
# This ensures migrations execute automatically during container initialization
COPY migrations/ /tmp/migrations/
RUN find /tmp/migrations -name "*.sql" -type f | sort -V | while read file; do \
      filename=$(basename "$file"); \
      cp "$file" "/docker-entrypoint-initdb.d/03-${filename}"; \
    done && \
    rm -rf /tmp/migrations

# Expose PostgreSQL port
EXPOSE 5432

# Health check to ensure database is ready
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB} || exit 1

# Default command (inherited from base image)
# CMD ["postgres"]
