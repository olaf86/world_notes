#!/bin/sh
set -e

# ---------------------------------------------------------------------------
# Install Flutter
# ---------------------------------------------------------------------------
FLUTTER_ROOT="$HOME/flutter"
git clone https://github.com/flutter/flutter.git \
    --depth 1 -b stable "$FLUTTER_ROOT"
export PATH="$PATH:$FLUTTER_ROOT/bin"

# ---------------------------------------------------------------------------
# Restore secret files
# GoogleService-Info.plist is stored as a base64-encoded secret env var.
# To encode: base64 -i GoogleService-Info.plist | pbcopy
# ---------------------------------------------------------------------------
echo "$GOOGLE_SERVICE_INFO_PLIST" | base64 --decode \
    > "$CI_PRIMARY_REPOSITORY_PATH/ios/Runner/GoogleService-Info.plist"

# ---------------------------------------------------------------------------
# Flutter dependencies & code generation
# ---------------------------------------------------------------------------
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

# Verify Generated.xcconfig was created by flutter pub get
if [ ! -f "$CI_PRIMARY_REPOSITORY_PATH/ios/Flutter/Generated.xcconfig" ]; then
  echo "ERROR: Generated.xcconfig was not created by flutter pub get"
  exit 1
fi

# ---------------------------------------------------------------------------
# CocoaPods — Xcode Cloud does not run pod install automatically.
# Delete Podfile.lock so CocoaPods resolves from the Podfile instead of
# verifying CDN checksums for Flutter plugin pods (which are path-only and
# not published to trunk, causing "Unable to find a specification" errors).
# ---------------------------------------------------------------------------
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
rm -f Podfile.lock
pod install

# ---------------------------------------------------------------------------
# Inject --dart-define values into Generated.xcconfig
# Flutter encodes each define as base64, joined with commas.
# Xcode Cloud sets env vars but doesn't pass them via flutter CLI,
# so we write DART_DEFINES manually after flutter pub get generates the file.
# ---------------------------------------------------------------------------
encode() { printf '%s' "$1" | base64; }

DART_DEFINES="$(encode "STADIA_API_KEY=$STADIA_API_KEY")\
,$(encode "REVENUECAT_API_KEY_IOS=$REVENUECAT_API_KEY_IOS")\
,$(encode "BANNER_AD_UNIT_ID=$BANNER_AD_UNIT_ID")"

echo "DART_DEFINES=$DART_DEFINES" \
    >> "$CI_PRIMARY_REPOSITORY_PATH/ios/Flutter/Generated.xcconfig"
