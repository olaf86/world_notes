#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SCREENSHOT_LOCALE="${SCREENSHOT_LOCALE:-ja}"
case "$SCREENSHOT_LOCALE" in
  en|ja|zh_Hant|zh_Hans|ko) ;;
  *)
    echo "SCREENSHOT_LOCALE must be en, ja, zh_Hant, zh_Hans, or ko." >&2
    exit 1
    ;;
esac
SCREENSHOT_OUTPUT_DIR="artifacts/store_screenshots/android/$SCREENSHOT_LOCALE"

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro command not found. Install Maestro CLI first." >&2
  exit 1
fi

echo "[1/3] Building and installing the current app..."
bash scripts/prepare_screenshot_app.sh android

echo "[2/3] Seeding screenshot data..."
(
  cd functions
  SCREENSHOT_LOCALE="$SCREENSHOT_LOCALE" npm run seed:screenshot
)

echo "[3/3] Running Maestro flow (Android)..."
mkdir -p "$SCREENSHOT_OUTPUT_DIR"
maestro test \
  -e SCREENSHOT_OUTPUT_DIR="$SCREENSHOT_OUTPUT_DIR" \
  maestro/screenshots/flows/android/store_screenshots.yaml

echo "Done: $SCREENSHOT_OUTPUT_DIR/"
