# Local Screenshot Automation (Maestro + Firebase Emulator)

## Purpose

- Capture App Store Connect and Google Play screenshots from stable local data.
- Keep screenshot data isolated from production Firebase.
- Keep store-image generation separate from the acceptance-test workspace.

## Structure

- UI automation: Maestro (`maestro/screenshots/` workspace)
- Data source: Firebase Emulator (Auth / Firestore / Functions / Storage)
- App mode: `flutter run` with `USE_FIREBASE_EMULATORS=true` and `SCREENSHOT_MODE=true`
- Screenshot output:
  - Android: `artifacts/store_screenshots/android/{locale}/`
  - iOS (1320 x 2868): `artifacts/store_screenshots/ios/{locale}/`
  - iPad (2064 x 2752): `artifacts/store_screenshots/ios_ipad/{locale}/`

`artifacts/store_screenshots/` is ignored by git.

## Runtime Flags

- `USE_FIREBASE_EMULATORS=true`
  - Connects Auth, Firestore, Functions, and Storage to local emulators.
  - Skips App Check activation in debug builds.
- `SCREENSHOT_MODE=true`
  - Signs in the screenshot user automatically.
  - Uses a fixed Tokyo Station location instead of GPS.
  - Skips notification startup and RevenueCat initialization.
  - Suppresses ad loading.
- `SCREENSHOT_AUTH_EMAIL`
  - Defaults to `screenshot@example.com`.
- `SCREENSHOT_AUTH_PASSWORD`
  - Defaults to `Passw0rd!`.
- `SCREENSHOT_LATITUDE` / `SCREENSHOT_LONGITUDE`
  - Defaults to Tokyo Station: `35.6812`, `139.7671`.
- `SCREENSHOT_LOCALE`
  - Supports `en`, `ja`, `zh_Hant`, `zh_Hans`, and `ko`; defaults to `ja`.
  - Forces the app UI locale and selects matching localized seed data.

## Seed Data

Seed data is defined in `functions/src/scripts/seedScreenshotData.ts` and
written by:

```bash
(cd functions && npm run seed:screenshot)
```

The script creates:

- A screenshot auth user.
- Public notes near Tokyo Station.
- A private note owned by the screenshot user.
- An archived note for the My Notes archive tab.
- Messages, visitors, and one nearby-alert mirror document.

The Maestro flows use the stable IDs:

- `wn_tokyo_station`
- `wn_marunouchi_cafe`
- `wn_imperial_garden`
- `wn_archived_memory`

## First-Time Setup

Install Flutter and Functions dependencies before starting the emulator:

```bash
flutter pub get
(cd functions && npm ci && npm run build)
```

## Android

1. Start Firebase Emulator:

   ```bash
   firebase emulators:start --project world-notes-prod --only auth,firestore,functions,storage
   ```

2. Run the app on a single Android emulator:

   ```bash
   flutter run \
     -d emulator-5554 \
     --dart-define=USE_FIREBASE_EMULATORS=true \
     --dart-define=SCREENSHOT_MODE=true \
     --dart-define=SCREENSHOT_LOCALE=ja \
     --dart-define=SCREENSHOT_AUTH_EMAIL=screenshot@example.com \
     --dart-define=SCREENSHOT_AUTH_PASSWORD=Passw0rd!
   ```

3. Capture screenshots:

   ```bash
   SCREENSHOT_LOCALE=ja ./scripts/run_screenshots_android.sh
   ```

## iOS

1. Start Firebase Emulator:

   ```bash
   firebase emulators:start --project world-notes-prod --only auth,firestore,functions,storage
   ```

2. Run the app on a single iPhone simulator:

   ```bash
   flutter run \
     -d "iPhone 17 Pro Max" \
     --dart-define=USE_FIREBASE_EMULATORS=true \
     --dart-define=SCREENSHOT_MODE=true \
     --dart-define=SCREENSHOT_LOCALE=ja \
     --dart-define=SCREENSHOT_AUTH_EMAIL=screenshot@example.com \
     --dart-define=SCREENSHOT_AUTH_PASSWORD=Passw0rd!
   ```

3. Capture screenshots:

   ```bash
   SCREENSHOT_LOCALE=ja ./scripts/run_screenshots_ios.sh
   SCREENSHOT_LOCALE=en ./scripts/run_screenshots_ios.sh
   SCREENSHOT_LOCALE=zh_Hant ./scripts/run_screenshots_ios.sh
   SCREENSHOT_LOCALE=zh_Hans ./scripts/run_screenshots_ios.sh
   SCREENSHOT_LOCALE=ko ./scripts/run_screenshots_ios.sh
   ```

   Restart `flutter run` with the matching `SCREENSHOT_LOCALE` before
   capturing the other language.

## iPad

1. Start Firebase Emulator:

   ```bash
   firebase emulators:start --project world-notes-prod --only auth,firestore,functions,storage
   ```

2. Run the app on an iPad simulator:

   ```bash
   flutter run \
     -d "iPad Pro 13-inch (M5)" \
     --dart-define=USE_FIREBASE_EMULATORS=true \
     --dart-define=SCREENSHOT_MODE=true \
     --dart-define=SCREENSHOT_LOCALE=ja \
     --dart-define=SCREENSHOT_AUTH_EMAIL=screenshot@example.com \
     --dart-define=SCREENSHOT_AUTH_PASSWORD=Passw0rd!
   ```

3. Capture screenshots:

   ```bash
   SCREENSHOT_LOCALE=ja ./scripts/run_screenshots_ipad.sh
   SCREENSHOT_LOCALE=en ./scripts/run_screenshots_ipad.sh
   SCREENSHOT_LOCALE=zh_Hant ./scripts/run_screenshots_ipad.sh
   SCREENSHOT_LOCALE=zh_Hans ./scripts/run_screenshots_ipad.sh
   SCREENSHOT_LOCALE=ko ./scripts/run_screenshots_ipad.sh
   ```

   Restart `flutter run` with the matching `SCREENSHOT_LOCALE` before
   capturing the other language.

## Smoke Test

After the app is running in screenshot mode and seed data exists:

```bash
maestro test --config=maestro/screenshots/config.yaml \
  maestro/screenshots/flows/smoke.yaml
```

## Notes

- Run only one simulator/emulator target at a time.
- Use `-d` with `flutter run` so Flutter does not pick the wrong device.
- The iOS scripts use `JAVA_HOME` when set and otherwise fall back to Android
  Studio's bundled JBR for Maestro.
- The store flows use `takeScreenshot`, so filenames are controlled by the YAML.
- If a flow stalls on map/list loading, confirm Firebase Emulator is running and seed data was inserted.
