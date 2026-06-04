#!/bin/sh
set -ex

# ---------------------------------------------------------------------------
# Install Flutter
# ---------------------------------------------------------------------------
FLUTTER_ROOT="$HOME/flutter"
git clone https://github.com/flutter/flutter.git \
    --depth 1 -b stable "$FLUTTER_ROOT"
export PATH="$PATH:$FLUTTER_ROOT/bin"

# Use CocoaPods for iOS plugins in CI. Xcode Cloud has been intermittently
# failing while resolving Firebase SwiftPM binary artifacts.
flutter config --no-enable-swift-package-manager

# ---------------------------------------------------------------------------
# Restore secret files
# GoogleService-Info.plist is stored as a base64-encoded secret env var.
# To encode: base64 -i GoogleService-Info.plist | pbcopy
# ---------------------------------------------------------------------------
if [ -z "${GOOGLE_SERVICE_INFO_PLIST:-}" ]; then
  echo "ERROR: GOOGLE_SERVICE_INFO_PLIST is not set"
  exit 1
fi

decode_base64() {
  if printf '' | base64 --decode >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

printf '%s' "$GOOGLE_SERVICE_INFO_PLIST" | decode_base64 \
  > "$CI_PRIMARY_REPOSITORY_PATH/ios/Runner/GoogleService-Info.plist"

# ---------------------------------------------------------------------------
# Flutter dependencies & code generation
# ---------------------------------------------------------------------------
flutter precache --ios

cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

if ! command -v pod >/dev/null 2>&1; then
  echo "ERROR: CocoaPods is not installed"
  exit 1
fi

cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
pod install
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Verify Generated.xcconfig was created by flutter pub get
if [ ! -f "$CI_PRIMARY_REPOSITORY_PATH/ios/Flutter/Generated.xcconfig" ]; then
  echo "ERROR: Generated.xcconfig was not created by flutter pub get"
  exit 1
fi

# ---------------------------------------------------------------------------
# Inject --dart-define values into Generated.xcconfig
# Flutter encodes each define as base64, joined with commas.
# Xcode Cloud sets env vars but doesn't pass them via flutter CLI,
# so we write DART_DEFINES manually after flutter pub get generates the file.
# ---------------------------------------------------------------------------
encode() { printf '%s' "$1" | base64 | tr -d '\n'; }

DART_DEFINES="$(encode "STADIA_API_KEY=$STADIA_API_KEY")\
,$(encode "REVENUECAT_API_KEY_IOS=$REVENUECAT_API_KEY_IOS")\
,$(encode "BANNER_AD_UNIT_ID=$BANNER_AD_UNIT_ID")"

echo "DART_DEFINES=$DART_DEFINES" \
    >> "$CI_PRIMARY_REPOSITORY_PATH/ios/Flutter/Generated.xcconfig"

# ---------------------------------------------------------------------------
# Clear SwiftPM binary artifact cache before Xcode Cloud starts archive/test.
# Xcode Cloud can restore a stale or partially-created artifact directory, and
# SwiftPM then fails with "already exists in file system" while downloading
# binary targets such as MapLibre.dynamic.xcframework.zip.
# ---------------------------------------------------------------------------
SWIFTPM_ARTIFACTS_CACHE="$HOME/Library/Caches/org.swift.swiftpm/artifacts"

if [ -n "$SWIFTPM_ARTIFACTS_CACHE" ] && [ -d "$SWIFTPM_ARTIFACTS_CACHE" ]; then
  rm -rf "$SWIFTPM_ARTIFACTS_CACHE"
fi

mkdir -p "$SWIFTPM_ARTIFACTS_CACHE"
