#!/bin/bash

set -e

PATH="${PATH}:${FLUTTER_ROOT}/bin:${PUB_CACHE:-$HOME/.pub-cache}/bin:$HOME/.pub-cache/bin"

crashlytics_run=""
derived_data_path=$(echo "${BUILD_ROOT:-}" | sed -E 's|(.*DerivedData/[^/]+).*|\1|')

candidates=(
  "${PODS_ROOT:-}/FirebaseCrashlytics/run"
  "${CI_DERIVED_DATA_PATH:-}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
  "${PROJECT_DIR}/../build/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
  "${BUILD_DIR:-}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
  "${derived_data_path}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
)

for candidate in "${candidates[@]}"; do
  if [[ -f "$candidate" ]]; then
    crashlytics_run="$candidate"
    break
  fi
done

if [[ -z "$crashlytics_run" ]]; then
  crashlytics_run=$(find \
    "${PROJECT_DIR}/../build/ios" \
    "${BUILD_DIR:-}" \
    "$derived_data_path" \
    -type f -path '*/firebase-ios-sdk/Crashlytics/run' -print -quit 2>/dev/null || true)
fi

if [[ -z "$crashlytics_run" || ! -f "$crashlytics_run" ]]; then
  echo "error: Firebase Crashlytics upload script was not found." >&2
  exit 1
fi

flutterfire upload-crashlytics-symbols \
  --upload-symbols-script-path="$crashlytics_run" \
  --platform=ios \
  --apple-project-path="${SRCROOT}" \
  --env-platform-name="${PLATFORM_NAME}" \
  --env-configuration="${CONFIGURATION}" \
  --env-project-dir="${PROJECT_DIR}" \
  --env-built-products-dir="${BUILT_PRODUCTS_DIR}" \
  --env-dwarf-dsym-folder-path="${DWARF_DSYM_FOLDER_PATH}" \
  --env-dwarf-dsym-file-name="${DWARF_DSYM_FILE_NAME}" \
  --env-infoplist-path="${INFOPLIST_PATH}" \
  --target=Runner
