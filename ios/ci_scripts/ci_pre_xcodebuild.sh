#!/bin/sh
set -ex

# Xcode Cloud can reuse or partially restore SwiftPM binary artifact cache
# directories between steps. SwiftPM then fails while downloading binary targets
# with "already exists in file system" for Firebase/Google artifacts.
SWIFTPM_ARTIFACTS_CACHE="$HOME/Library/Caches/org.swift.swiftpm/artifacts"

if [ -n "$SWIFTPM_ARTIFACTS_CACHE" ] && [ -d "$SWIFTPM_ARTIFACTS_CACHE" ]; then
  rm -rf "$SWIFTPM_ARTIFACTS_CACHE"
fi

mkdir -p "$SWIFTPM_ARTIFACTS_CACHE"
