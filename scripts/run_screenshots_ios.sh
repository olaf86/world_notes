#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro command not found. Install Maestro CLI first." >&2
  exit 1
fi

echo "[1/2] Seeding screenshot data..."
(
  cd functions
  npm run seed:screenshot
)

echo "[2/2] Running Maestro flow (iOS)..."
maestro test maestro/flows/ios/store_screenshots.yaml

echo "Done: artifacts/store_screenshots/ios/"
