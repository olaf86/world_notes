#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ACCEPTANCE_AUTH_EMAIL="${ACCEPTANCE_AUTH_EMAIL:-acceptance@example.com}"
ACCEPTANCE_AUTH_PASSWORD="${ACCEPTANCE_AUTH_PASSWORD:-Passw0rd!}"
ACCEPTANCE_TAGS="${ACCEPTANCE_TAGS:-smoke}"
RUN_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ACCEPTANCE_RESULT_DIR="${ACCEPTANCE_RESULT_DIR:-$ROOT_DIR/artifacts/acceptance/$RUN_TIMESTAMP}"

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro command not found. Install Maestro CLI first." >&2
  exit 1
fi

echo "[1/2] Seeding acceptance data..."
(
  cd functions
  ACCEPTANCE_AUTH_EMAIL="$ACCEPTANCE_AUTH_EMAIL" \
    ACCEPTANCE_AUTH_PASSWORD="$ACCEPTANCE_AUTH_PASSWORD" \
    npm run seed:acceptance
)

echo "[2/2] Running Maestro acceptance flows (tags: $ACCEPTANCE_TAGS)..."
mkdir -p "$ACCEPTANCE_RESULT_DIR/maestro"
maestro test \
  --config=maestro/acceptance/config.yaml \
  --include-tags="$ACCEPTANCE_TAGS" \
  --format=junit \
  --output="$ACCEPTANCE_RESULT_DIR/report.xml" \
  --test-output-dir="$ACCEPTANCE_RESULT_DIR/maestro" \
  --debug-output="$ACCEPTANCE_RESULT_DIR/maestro" \
  -e ACCEPTANCE_AUTH_EMAIL="$ACCEPTANCE_AUTH_EMAIL" \
  -e ACCEPTANCE_AUTH_PASSWORD="$ACCEPTANCE_AUTH_PASSWORD" \
  maestro/acceptance

echo "Done: $ACCEPTANCE_RESULT_DIR"
