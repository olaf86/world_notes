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
SCREENSHOT_OUTPUT_DIR="artifacts/store_screenshots/ios/$SCREENSHOT_LOCALE"

if [[ -z "${JAVA_HOME:-}" ]] &&
  [[ -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro command not found. Install Maestro CLI first." >&2
  exit 1
fi

if command -v xcrun >/dev/null 2>&1; then
  xcrun simctl terminate booted dev.asobo.worldnotes >/dev/null 2>&1 || true
  sleep 1
fi

echo "[1/2] Seeding screenshot data..."
seed_screenshot_data() {
  (
    cd functions
    SCREENSHOT_LOCALE="$SCREENSHOT_LOCALE" npm run seed:screenshot
  )
}
if ! seed_screenshot_data; then
  echo "Seed attempt failed; retrying once..."
  sleep 1
  seed_screenshot_data
fi

echo "[2/2] Running Maestro flow (iOS)..."
mkdir -p "$SCREENSHOT_OUTPUT_DIR"
maestro test \
  -e SCREENSHOT_OUTPUT_DIR="$SCREENSHOT_OUTPUT_DIR" \
  maestro/screenshots/flows/ios/store_screenshots.yaml

echo "Done: $SCREENSHOT_OUTPUT_DIR/"
