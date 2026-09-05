#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SCREENSHOT_PLATFORM="${1:-}"
SCREENSHOT_LOCALE="${SCREENSHOT_LOCALE:-ja}"
SCREENSHOT_AUTH_EMAIL="${SCREENSHOT_AUTH_EMAIL:-screenshot@example.com}"
SCREENSHOT_AUTH_PASSWORD="${SCREENSHOT_AUTH_PASSWORD:-Passw0rd!}"

case "$SCREENSHOT_LOCALE" in
  en|ja|zh_Hant|zh_Hans|ko) ;;
  *)
    echo "SCREENSHOT_LOCALE must be en, ja, zh_Hant, zh_Hans, or ko." >&2
    exit 1
    ;;
esac

dart_defines=(
  "--dart-define=USE_FIREBASE_EMULATORS=true"
  "--dart-define=SCREENSHOT_MODE=true"
  "--dart-define=SCREENSHOT_LOCALE=$SCREENSHOT_LOCALE"
  "--dart-define=SCREENSHOT_AUTH_EMAIL=$SCREENSHOT_AUTH_EMAIL"
  "--dart-define=SCREENSHOT_AUTH_PASSWORD=$SCREENSHOT_AUTH_PASSWORD"
)

case "$SCREENSHOT_PLATFORM" in
  ios)
    if ! command -v xcrun >/dev/null 2>&1; then
      echo "xcrun command not found. Install Xcode first." >&2
      exit 1
    fi

    booted_count="$(
      xcrun simctl list devices booted |
        awk '/\(Booted\)/ { count++ } END { print count + 0 }'
    )"
    if [[ "$booted_count" -ne 1 ]]; then
      echo "Exactly one iOS simulator must be booted; found $booted_count." >&2
      exit 1
    fi

    xcrun simctl terminate booted dev.asobo.worldnotes >/dev/null 2>&1 || true
    xcrun simctl ui booted appearance light
    flutter build ios \
      --simulator \
      --debug \
      "${dart_defines[@]}"
    xcrun simctl install booted build/ios/iphonesimulator/Runner.app
    ;;
  android)
    if ! command -v adb >/dev/null 2>&1; then
      echo "adb command not found. Install Android platform tools first." >&2
      exit 1
    fi

    connected_count="$(
      adb devices |
        awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }'
    )"
    if [[ "$connected_count" -ne 1 ]]; then
      echo "Exactly one Android device must be connected; found $connected_count." >&2
      exit 1
    fi

    adb shell am force-stop dev.asobo.worldnotes
    adb shell cmd uimode night no
    flutter build apk \
      --debug \
      "${dart_defines[@]}" \
      "--dart-define=GOOGLE_MAPS_API_KEY=${GOOGLE_MAPS_API_KEY:-}"
    adb install -r build/app/outputs/flutter-apk/app-debug.apk
    ;;
  *)
    echo "Usage: $0 <ios|android>" >&2
    exit 1
    ;;
esac
