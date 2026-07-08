# World Notes

A location-based diary app built with Flutter. Drop notes on a map, revisit them when you return, and share messages with other users who visit the same place.

## Features

- Interactive map powered by MapLibre GL + Stadia Maps
- Drop notes at any location with a title, content, and color
- Message board at each note — visible to anyone who visits the spot
- Google Sign-In via Firebase Auth
- World Notes PRO subscription (ad-free + 200 active notes) via RevenueCat
- Banner ads for free-tier users via Google Mobile Ads

## Tech Stack

- **Flutter** (Dart)
- **Firebase** — Auth, Firestore, Storage
- **MapLibre GL** — map rendering
- **Stadia Maps** — map tiles
- **Riverpod** — state management
- **GoRouter** — navigation
- **RevenueCat** — in-app subscriptions
- **Google Mobile Ads** — banner ads

## Getting Started

### Prerequisites

- Flutter SDK `^3.11.0`
- Firebase project with Auth and Firestore enabled
- Stadia Maps API key
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
   flutter run --dart-define=STADIA_API_KEY=your_key \
               --dart-define=REVENUECAT_API_KEY_IOS=your_key

   # Android
   flutter run --dart-define=STADIA_API_KEY=your_key \
               --dart-define=REVENUECAT_API_KEY_ANDROID=your_key
   ```

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
| `STADIA_API_KEY` | Stadia Maps API key |
| `REVENUECAT_API_KEY_ANDROID` | RevenueCat Android public key |
| `BANNER_AD_UNIT_ID` | AdMob banner unit ID |

### Maestro UI Testing and Screenshots

Maestro flows live in `maestro/flows/`.

```bash
# Smoke test after launching the app in screenshot mode
maestro test maestro/flows/smoke.yaml

# Store screenshots after Firebase Emulator + flutter run are active
./scripts/run_screenshots_ios.sh
./scripts/run_screenshots_ipad.sh
./scripts/run_screenshots_android.sh
```

See [internal-docs/local-screenshot-with-maestro.md](internal-docs/local-screenshot-with-maestro.md)
for the Firebase Emulator setup, screenshot seed data, and platform-specific
capture steps.

### Environment Variables

All secrets are injected at build time via `--dart-define`. No `.env` file is used.

| Key | Description |
|-----|-------------|
| `STADIA_API_KEY` | Stadia Maps API key |
| `REVENUECAT_API_KEY_IOS` | RevenueCat iOS public key |
| `REVENUECAT_API_KEY_ANDROID` | RevenueCat Android public key |
| `BANNER_AD_UNIT_ID` | AdMob banner unit ID (defaults to Google test ID) |

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
