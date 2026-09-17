# Android release operations

## Signing model

World Notes uses Google Play App Signing with a separate upload key. Google
holds the app-signing key used for Play-distributed APKs; the local and CI
keystore authenticates AAB uploads only.

Release builds must never fall back to the Android debug key. Gradle accepts
release credentials from either the ignored `android/key.properties` file or
these CI environment variables:

- `ANDROID_KEYSTORE_PATH`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

## Create the upload key with Android Studio

For the one-time interactive setup, Android Studio is the simplest option:

1. Open `/Users/olaf/Repos/world_notes/android` as an Android project in
   Android Studio. Opening only this directory avoids indexing unrelated iOS
   and generated Flutter files and ensures that the `app` Android module is
   available to the signed-bundle wizard.
2. Select **Build > Generate Signed Bundle / APK**.
3. Select **Android App Bundle**, then select the `app` module.
4. Select **Create new** below the keystore-path field.
5. Save the keystore as
   `~/.android/keystores/world-notes-upload.jks`.
6. Use `world-notes-upload` as the alias, use the same strong password for the
   keystore and key, and select a validity of 100 years. Android requires at
   least 25 years; the longer validity avoids an unnecessary upload-certificate
   expiry during the app's lifetime.
7. For the certificate fields, use the personal Play developer's real name for
   **First and Last Name**, `Mobile Development` for **Organizational Unit**,
   the Play Console developer name for **Organization**, the developer's real
   city/prefecture, and `JP` for **Country Code**. These values identify the
   upload certificate; Google Play does not use them to verify account ownership.

Android Studio passes the signing values to Gradle for that build without
writing them to source control. After creating the final key, copy
`android/key.properties.example` to the ignored `android/key.properties` file
and set `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`. Restrict it
to owner-only access with `chmod 600 android/key.properties`. Never commit the
file or attach it to an issue or chat.

## Build locally

Copy the tracked template to the ignored local configuration and replace every
placeholder with the Android production value:

```bash
cp .dart_define.example.json .dart_define.json
flutter build appbundle --release \
  --dart-define-from-file=.dart_define.json
```

The output is `build/app/outputs/bundle/release/app-release.aab`.
Release builds fail before compilation if signing or any production runtime
value is missing. Android Studio's signed-bundle wizard is therefore for the
one-time key setup; use the Flutter command above for the uploadable bundle.

## Configure GitHub Actions

The manual `Android release AAB` workflow requires these repository secrets:

- `ANDROID_UPLOAD_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `GOOGLE_MAPS_API_KEY`
- `REVENUECAT_API_KEY_ANDROID`
- `ADMOB_ANDROID_APP_ID_PROD`
- `ADMOB_ANDROID_BANNER_AD_UNIT_ID_PROD`
- `ADMOB_ANDROID_INTERSTITIAL_AD_UNIT_ID_PROD`

Encode the keystore without line wrapping before saving the base64 value as a
GitHub Actions secret:

```bash
base64 < ~/.android/keystores/world-notes-upload.jks | tr -d '\n'
```

The workflow validates every required secret before building, restores the
keystore under the runner's temporary directory, runs analysis and tests, and
uploads the signed AAB as a short-lived build artifact. It does not publish to
Google Play automatically.

## First Play upload

Upload the signed AAB to the internal-test release page. Do not roll the first
release out until Play Console finishes its automated checks and the installed
build has the required runtime configuration.

After Play App Signing is active, copy the Play-managed signing certificate
fingerprints into Firebase Authentication, the restricted Google Maps key, and
`public/.well-known/assetlinks.json`. Register every fingerprint shown for the
Play-managed signing keys, not only the local upload-key fingerprint.
