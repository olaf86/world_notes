# App Review resubmission — September 2, 2026

This runbook addresses Submission ID
`d338c3da-cf97-4d80-91b0-5fbb8dc2d0ee`, version `1.0.0 (109)`:

- Guideline 2.1: ATT prompt not found on iPadOS 26.6.
- Guideline 3.1.2(c): functional Privacy Policy and Terms of Use links missing
  from the in-app subscription flow.

## Changes in the replacement build

- iOS calls `ATTrackingManager.requestTrackingAuthorization` directly after
  the UMP consent form finishes and before `MobileAds.initialize`.
- The native request waits until the application is active. An existing ATT
  decision is returned without showing another prompt.
- The first location permission request waits for the ad privacy flow, avoiding
  concurrent system permission dialogs.
- The RevenueCat purchase screen has a persistent footer with functional links
  to:
  - Privacy Policy: `https://worldnotes.asobo.dev/privacy/`
  - Terms of Use (Apple Standard EULA):
    `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`

ATT is intentionally requested only for an authenticated, non-PRO account
because PRO accounts do not receive ads and are not tracked for advertising.

## App Store Connect checks

Before selecting the replacement build:

1. Set the Privacy Policy field to
   `https://worldnotes.asobo.dev/privacy/`.
2. Confirm every localized App Description contains the complete Apple
   Standard EULA URL:
   `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`.
3. Keep the applicable advertising data types marked as used for tracking in
   App Privacy. This build still uses tracking for non-PRO ads.
4. Confirm the review account is a non-PRO account and provide working
   credentials. A PRO account correctly does not show ATT.
5. Confirm the release build received non-empty production banner,
   interstitial, and RevenueCat keys from Xcode Cloud.

## Required physical-device recording

Use a physical iPad if possible, matching the review device class. Do not use
the simulator for the evidence recording.

1. In Settings → Privacy & Security → Tracking, enable **Allow Apps to
   Request to Track**.
2. Delete World Notes from the device to clear its one-time ATT decision.
3. Start screen recording before installing or launching the replacement
   build.
4. Install and launch the build, then sign in with the non-PRO review account.
5. Record the UMP flow if shown, followed by the native ATT prompt.
6. Choose either ATT option and continue until the map flow begins. The
   location prompt must appear only after ATT has completed.
7. Open World Notes PRO and record both legal links on the purchase screen.
8. Tap each link and show that the Privacy Policy and Apple Standard EULA load.
9. Attach the recording to the App Review reply and add it to **App Review
   Information → Notes** for the new submission.

## App Review Information — Notes

Replace `<NEW_BUILD_NUMBER>` and `<REVIEW_ACCOUNT_PATH>` before pasting:

```text
Guideline 2.1 — App Tracking Transparency

In version 1.0.0 (<NEW_BUILD_NUMBER>), the app directly requests App Tracking
Transparency authorization for authenticated non-PRO users after the Google
UMP consent flow and before the Google Mobile Ads SDK is initialized or any ad
is requested. The first location permission request is deferred until the ATT
flow has completed so the system permission dialogs cannot overlap.

Fresh-install test path:
1. Launch the app.
2. Sign in using the review account: <REVIEW_ACCOUNT_PATH>.
3. Complete the consent/ATT prompt.
4. Continue to the map; the location prompt follows ATT.

PRO users are not shown ATT because they do not receive advertising. The review
account is non-PRO.

Guideline 3.1.2(c) — Auto-renewable subscriptions

The World Notes PRO purchase screen now permanently displays functional links
to the Privacy Policy and Terms of Use (Apple Standard EULA) below the purchase
options. Both links can be opened directly from the purchase flow.

Privacy Policy: https://worldnotes.asobo.dev/privacy/
Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

A physical-device screen recording demonstrating both flows is attached.
```

## Reply to the reviewer

Replace `<NEW_BUILD_NUMBER>` before sending:

```text
Hello,

Thank you for the detailed review. We addressed both issues in version 1.0.0
(<NEW_BUILD_NUMBER>).

For Guideline 2.1, the app now directly requests App Tracking Transparency
authorization for non-PRO users after the UMP consent flow and before the
Google Mobile Ads SDK is initialized. We also ensure that the location
permission prompt cannot overlap the ATT request.

For Guideline 3.1.2(c), the subscription purchase screen now includes visible,
functional links to our Privacy Policy and the Apple Standard EULA.

We attached a screen recording captured on a physical device showing a fresh
install, the ATT request and following user flow, and both links opening from
the subscription screen. We also included these details in the App Review
Information Notes field.

Thank you.
```
