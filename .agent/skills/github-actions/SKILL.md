---
name: github-actions
description: Designing and developing GitHub Actions workflows for CI/CD, database migrations, Docker publishing, and automated deployments in the xq-fitness project.
---

# GitHub Actions Skill

Use this skill when creating, modifying, or debugging GitHub Actions workflows.

## Workflow Location

All workflows live in `.github/workflows/`. Filenames should be kebab-case and descriptive:
```
.github/workflows/
├── publish-docker.yml      # Build & push Docker image to GHCR
└── migrate-to-neon.yml     # Deploy schema/migrations to Neon (production)
```

---

## 1. Workflow Patterns

### Naming & Triggers

```yaml
name: Human Readable Workflow Name    # Shows in GitHub UI

on:
  push:                               # Auto-trigger on push
    branches: [main, master]
  workflow_dispatch:                   # Manual trigger with inputs
    inputs:
      mode:
        description: 'Operation mode'
        required: true
        type: choice
        options: [option-a, option-b]
      confirm:
        description: 'Type "yes" to confirm'
        required: true
        type: string
```

### Destructive Operations — Confirmation Gate

All workflows that modify production resources **must** include a validation job with manual confirmation:

```yaml
jobs:
  validate:
    name: Validate Request
    runs-on: ubuntu-latest
    steps:
      - name: Check confirmation
        run: |
          if [[ "${{ github.event.inputs.confirm }}" != "yes" ]]; then
            echo "❌ Not confirmed. Please type 'yes' in the confirm field."
            exit 1
          fi
          echo "✓ Confirmed"

      - name: Display plan
        run: |
          echo "Plan:"
          echo "  Mode: ${{ github.event.inputs.mode }}"
          echo "  Target: Production Database"
          echo "  Triggered by: ${{ github.actor }}"
          echo "  Commit: ${{ github.sha }}"

  execute:
    needs: validate            # Gate on validation
    runs-on: ubuntu-latest
    # ... actual work
```

---

## 2. Job Structure

### Standard Job Template

```yaml
jobs:
  job-name:
    name: Human Readable Job Name
    runs-on: ubuntu-latest
    permissions:
      contents: read           # Minimal permissions
      packages: write          # Only if pushing to GHCR

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      # ... work steps ...

      - name: Summary
        if: success()
        run: |
          echo "✓ Completed successfully!"
          echo "  Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

      - name: Notify on failure
        if: failure()
        run: |
          echo "❌ Failed! Check logs above."
          exit 1
```

### Multi-Job Dependencies

```yaml
jobs:
  validate:
    # ... validation logic

  execute:
    needs: validate          # Runs after validate succeeds
    # ... execution logic

  cleanup:
    needs: execute
    if: always()             # Always run cleanup
    # ... cleanup logic
```

---

## 3. Secrets & Environment Variables

### Conventions

- Secrets are stored in GitHub → Settings → Secrets → Actions
- Reference with `${{ secrets.SECRET_NAME }}`
- **Never** echo secrets — use masking or indirect references
- Environment variables at job level for shared config:

```yaml
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: xq-fitness-db

jobs:
  build:
    env:
      DB_HOST: ${{ secrets.DB_HOST }}
      DB_PORT: ${{ secrets.DB_PORT }}
```

### Current Secrets Used

| Secret | Used In | Purpose |
|--------|---------|---------|
| `NEON_DATABASE_URL` | migrate-to-neon | Neon connection string |
| `DB_USER_AD`, `DB_PASSWORD_AD` | migrate-to-neon | Neon app user credentials |
| `GITHUB_TOKEN` | publish-docker | GHCR authentication (auto-provided) |

---

## 4. Docker Workflows

### Build & Push to GHCR

```yaml
steps:
  - name: Set up Docker Buildx
    uses: docker/setup-buildx-action@v3

  - name: Log in to GHCR
    uses: docker/login-action@v3
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}

  - name: Extract git hash
    id: git
    run: echo "short_hash=$(git rev-parse --short HEAD)" >> $GITHUB_OUTPUT

  - name: Build and push
    uses: docker/build-push-action@v5
    with:
      context: .
      push: true
      tags: |
        ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:${{ steps.git.outputs.short_hash }}
        ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:latest
      cache-from: type=gha
      cache-to: type=gha,mode=max
```

### Key Actions Used

| Action | Version | Purpose |
|--------|---------|---------|
| `actions/checkout` | v4 | Clone repository |
| `docker/setup-buildx-action` | v3 | Multi-platform Docker builds |
| `docker/login-action` | v3 | Auth to container registries |
| `docker/build-push-action` | v5 | Build and push images |

---

## 5. Database Migration Workflows

Production migrations use Neon via `migrate-to-neon.yml` and `scripts/migrate-to-neon.sh`.

### Neon Pattern (Direct Connection)

Neon doesn't need IP whitelisting but may need cold-start retry:

```yaml
- name: Verify connection
  run: |
    if ! psql "$NEON_DATABASE_URL" -c "SELECT version();" > /dev/null 2>&1; then
      sleep 5    # Cold start retry
      psql "$NEON_DATABASE_URL" -c "SELECT version();"
    fi
```

### Post-Migration Verification

Always verify database state after migration:

```yaml
- name: Verify database state
  run: |
    TABLES=$(psql "$DB_URL" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
    echo "Found $(echo $TABLES | xargs) tables"
    psql "$DB_URL" -c "\dt"
```

---

## 6. Design Guidelines

### Status Messaging

- Use `✓` for success, `❌` for failure, `⚠️` for warnings
- Echo a plan summary before executing
- Echo a results summary after completion
- Include timestamp: `$(date -u '+%Y-%m-%d %H:%M:%S UTC')`

### Error Handling

- Use `set -e` in multi-line scripts (or check exit codes explicitly)
- Use `if: always()` for cleanup steps
- Use `|| true` for non-critical failures that shouldn't stop the workflow
- Provide actionable error messages

### Permissions

- Follow least-privilege: only request `contents: read` and `packages: write` when needed
- Don't request `write` permissions unless pushing artifacts

### Mode/Switch Pattern

For workflows with multiple operation modes:

```yaml
case "${{ github.event.inputs.mode }}" in
  option-a)
    echo "Running option A..."
    ./scripts/do-a.sh
    ;;
  option-b)
    echo "Running option B..."
    ./scripts/do-b.sh
    ;;
  *)
    echo "Unknown mode: ${{ github.event.inputs.mode }}"
    exit 1
    ;;
esac
```
