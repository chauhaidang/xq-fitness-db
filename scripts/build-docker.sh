#!/usr/bin/env bash
set -euo pipefail

# Build Docker image for local database testing
# Usage: ./build-docker.sh

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATABASE_DIR="$SCRIPT_DIR/.."

# Verify Docker is installed and available
if ! command -v docker >/dev/null; then
  echo "❌ Docker is not installed or not in PATH" >&2
  echo "   Please install Docker: https://docs.docker.com/get-docker/" >&2
  exit 1
fi

# Verify Docker daemon is running
if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker daemon is not running" >&2
  echo "   Please start Docker and try again" >&2
  exit 1
fi

echo ">> Building Docker image for local database testing"
echo "   Image: xq-fitness-db:latest"
echo "   Context: $DATABASE_DIR"

# Build the Docker image
echo ">> Building image..."
if docker build -t xq-fitness-db:latest "$DATABASE_DIR"; then
  echo ""
  echo "✓ Docker image built successfully!"
  echo "   Image: xq-fitness-db:latest"
  echo ""
else
  EXIT_CODE=$?
  echo ""
  echo "❌ Docker image build failed with exit code $EXIT_CODE"
  echo "   Check the errors above for details"
  exit 1
fi

