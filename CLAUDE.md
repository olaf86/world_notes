# World Notes — CLAUDE.md

## Overview
A location-based diary app. Users drop notes on a map at specific places and share messages with others who visit the same location.

## Tech Stack

| Role | Library |
|------|---------|
| Map | `maplibre_gl` + Stadia Maps |
| Backend | Firebase Auth / Firestore / Storage |
| State management | Riverpod (`flutter_riverpod` + `riverpod_annotation`) |
| Navigation | GoRouter |
| Ads | Google Mobile Ads (non-premium users only) |
| Subscriptions | RevenueCat v10 (`purchases_flutter`) |
| Location | geolocator + permission_handler |

## Directory Structure

```
lib/
├── config/
│   ├── app_config.dart       # Constants & API keys (injected via --dart-define)
│   └── router.dart           # GoRouter definition
├── core/
│   ├── theme/app_theme.dart
│   └── utils/geohash_util.dart
├── domain/
│   ├── entities/             # Business logic entities (pure Dart, no Firebase)
│   └── repositories/         # Repository interfaces (abstract classes)
├── data/
│   ├── models/               # Firestore mapping models (fromJson/toJson)
│   └── repositories/         # Repository implementations (Firebase-dependent)
├── presentation/
│   ├── providers/providers.dart   # All Riverpod providers
│   ├── screens/
│   │   ├── auth/sign_in_screen.dart
│   │   ├── map/map_screen.dart
│   │   ├── note/note_box_screen.dart      # Note detail + message list
│   │   ├── note/note_creation_screen.dart
│   │   ├── profile/profile_screen.dart
│   │   └── subscription/subscription_screen.dart
│   └── widgets/
│       ├── map/note_marker_bottom_sheet.dart
│       └── note/message_bubble.dart
├── services/
│   ├── location_service.dart
│   └── subscription_service.dart
└── main.dart
```

## Build Commands

```bash
# Install dependencies
flutter pub get

# Code generation (Riverpod annotations)
dart run build_runner build --delete-conflicting-outputs

# Run on iOS
flutter run --dart-define=STADIA_API_KEY=xxx \
            --dart-define=REVENUECAT_API_KEY_IOS=xxx

# Run on Android
flutter run --dart-define=STADIA_API_KEY=xxx \
            --dart-define=REVENUECAT_API_KEY_ANDROID=xxx

# Lint
flutter analyze

# Tests
flutter test
```

## Environment Variables (injected via --dart-define)

| Key | Description | Default |
|-----|-------------|---------|
| `STADIA_API_KEY` | Stadia Maps API key | empty (omit for dev) |
| `REVENUECAT_API_KEY_IOS` | RevenueCat iOS key | empty |
| `REVENUECAT_API_KEY_ANDROID` | RevenueCat Android key | empty |
| `BANNER_AD_UNIT_ID` | AdMob banner ad unit ID | Google test ID |

## Firebase Setup (not yet done)

```bash
firebase init
flutterfire configure
```

Files generated:
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`

## Firestore Data Model

```
places/{placeId}
  title: string
  latitude: double
  longitude: double
  geohash: string          # precision=5 (~1.2km)
  createdBy: string        # uid
  createdAt: timestamp

notes/{noteId}
  placeId: string
  authorId: string
  content: string
  color: int               # Color.value
  isPublic: boolean
  createdAt: timestamp

messages/{messageId}
  noteId: string
  senderId: string
  text: string
  imageUrl: string?
  createdAt: timestamp

users/{uid}
  displayName: string
  photoUrl: string?
  isPremium: boolean
  createdAt: timestamp
```

## Architecture Rules

- **Dependency direction**: `domain/` must not import Firebase or any `data/` package
- **Providers**: all Riverpod providers live in `presentation/providers/providers.dart`
- **Geohash proximity search**: use `GeohashUtil.neighborHashes()` to get adjacent cells, then query Firestore with `where('geohash', whereIn: hashes)`
- **Premium check**: read `isPremiumProvider` in UI; source of truth is `SubscriptionService`

## iOS Info.plist (not yet done)

Add to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to show notes near your current location.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Used to notify you of nearby notes in the background.</string>
```

## RevenueCat Product IDs

- Monthly: `world_notes_premium_monthly`
- Yearly: `world_notes_premium_yearly`
- Entitlement ID: `premium`

## Remaining Setup

1. Create Firebase project → `flutterfire configure`
2. Obtain Stadia Maps API key
3. Configure RevenueCat products in App Store Connect / Google Play
4. Add location permission strings to iOS Info.plist
5. Write Firestore security rules
6. Create AdMob account → replace test banner ID with production ID
