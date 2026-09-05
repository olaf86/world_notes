# World Notes

A location-based diary app built with Flutter. Drop notes on a map, revisit them when you return, and share messages with other users who visit the same place.

## Features

- Native maps powered by Google Maps SDK on Android and MapKit on iOS
- Drop notes at any location with a title, content, and color
- Message board at each note — visible to anyone who visits the spot
- Google Sign-In via Firebase Auth
- World Notes PRO subscription (ad-free + 200 active notes) via RevenueCat
- Banner ads for free-tier users via Google Mobile Ads

## Tech Stack

- **Flutter** (Dart)
- **Firebase** — Auth, Firestore, Storage
- **Google Maps SDK** — Android map rendering
- **MapKit** — iOS map rendering
- **Riverpod** — state management
- **GoRouter** — navigation
- **RevenueCat** — in-app subscriptions
- **Google Mobile Ads** — banner ads

## Getting Started

### Prerequisites

- Flutter SDK `^3.11.0`
- Firebase project with Auth and Firestore enabled
- Google Cloud project with billing and Maps SDK for Android enabled
- RevenueCat account (optional for development)

### Setup

1. **Clone and install dependencies**

   ```bash
   git clone <repo-url>
   cd world_notes
   flutter pub get
   ```

2. **Configure Firebase**

   ```bash
   firebase init
   flutterfire configure
   ```

   This generates `google-services.json`, `GoogleService-Info.plist`, and `lib/firebase_options.dart`.

3. **Run code generation**

   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Run the app**

   ```bash
   # iOS
   flutter run --dart-define=REVENUECAT_API_KEY_IOS=your_key

   # Android
   flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key \
               --dart-define=REVENUECAT_API_KEY_ANDROID=your_key
   ```

   Restrict the Android key to the app's package name and signing certificate.
   The app intentionally does not configure a Google Map ID. Under the current
   Google Maps Platform pricing, native Maps SDK loads without a Map ID have an
   unlimited free usage cap; billing must still be enabled. Street View, Places,
   and other separately billed APIs are not used by the map rendering layer.

### Android CI

GitHub Actions builds a debug APK on pull requests, pushes to `main` and manual workflow runs. The workflow runs:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The generated `world-notes-debug-apk` artifact can be downloaded from the
workflow run and installed on a test device.

Optional repository secrets:

| Secret | Description |
|--------|-------------|
| `GOOGLE_MAPS_API_KEY` | Maps SDK for Android API key |
| `REVENUECAT_API_KEY_ANDROID` | RevenueCat Android public key |
| `ADMOB_ANDROID_APP_ID_PROD` | Production AdMob Android app ID |
| `ADMOB_ANDROID_BANNER_AD_UNIT_ID_PROD` | Production Android banner unit ID |
| `ADMOB_ANDROID_INTERSTITIAL_AD_UNIT_ID_PROD` | Production Android interstitial unit ID |

### Maestro Acceptance Tests

Acceptance flows and store-screenshot flows are separate Maestro workspaces.
The acceptance suite exercises normal sign-in against Firebase Emulator data;
it does not use `SCREENSHOT_MODE`.

```bash
# Launch the app in acceptance mode in one terminal
flutter run \
  --dart-define=USE_FIREBASE_EMULATORS=true \
  --dart-define=ACCEPTANCE_TEST_MODE=true

# Seed the acceptance account and run P0 smoke flows in another terminal
./scripts/run_acceptance_tests.sh
```

JUnit reports, failure screenshots, and logs are written under
`artifacts/acceptance/`. See
[`internal-docs/acceptance/test-policy.md`](internal-docs/acceptance/test-policy.md)
for priorities, coverage, and manual-test boundaries.

### Store Screenshots

Screenshot flows use the isolated `maestro/screenshots/` workspace and
`SCREENSHOT_MODE=true`.

```bash
# Screenshot-environment smoke check
maestro test --config=maestro/screenshots/config.yaml \
  maestro/screenshots/flows/smoke.yaml

# Store screenshots after Firebase Emulator is active and one target device is booted
./scripts/run_screenshots_ios.sh
./scripts/run_screenshots_ipad.sh
./scripts/run_screenshots_android.sh
```

Each script builds the current checkout with the screenshot runtime flags,
installs it on the sole booted target, forces light appearance, seeds local
data, and then runs Maestro. This prevents a stale installed app from being
captured.

See [internal-docs/local-screenshot-with-maestro.md](internal-docs/local-screenshot-with-maestro.md)
for the Firebase Emulator setup, screenshot seed data, and platform-specific
capture steps.

### Environment Variables

Runtime values are injected at build time; no `.env` file is used. Flutter
values use `--dart-define`, while native AdMob app IDs use platform build
settings.

| Key | Description |
|-----|-------------|
| `GOOGLE_MAPS_API_KEY` | Maps SDK for Android API key |
| `REVENUECAT_API_KEY_IOS` | RevenueCat iOS public key |
| `REVENUECAT_API_KEY_ANDROID` | RevenueCat Android public key |
| `BANNER_AD_UNIT_ID` | Platform production banner unit ID (release only) |
| `INTERSTITIAL_AD_UNIT_ID` | Platform production interstitial unit ID (release only) |

Debug and profile builds always use Google's official demo ad units. Xcode
Cloud maps `ADMOB_IOS_BANNER_AD_UNIT_ID_PROD` and
`ADMOB_IOS_INTERSTITIAL_AD_UNIT_ID_PROD` to the two Dart defines above, and
injects `IOS_ADMOB_APP_ID_PROD` into the iOS build setting used by Info.plist.

## Project Structure

```
lib/
├── config/        # App constants, GoRouter
├── core/          # Theme, Geohash utilities
├── domain/        # Entities and repository interfaces
├── data/          # Firestore models and repository implementations
├── presentation/  # Screens, widgets, Riverpod providers
└── services/      # Location, subscription services
```

See [CLAUDE.md](CLAUDE.md) for full architecture details.

## RevenueCat Products

World Notes PRO uses the `pro` entitlement.

| Product | ID | Price |
|---------|----|-------|
| Monthly | `world_notes_pro_monthly` | ¥300/month (about $2/month) |
| Yearly | `world_notes_pro_yearly` | ¥2,980/year (about $20/year) |

Launch offer:

| Offer | Product | Price |
|-------|---------|-------|
| Introductory first year | `world_notes_pro_yearly` | ¥1,980 for the first year, then ¥2,980/year |

## License

MIT
