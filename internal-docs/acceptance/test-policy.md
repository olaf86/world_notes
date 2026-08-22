# Acceptance Test Policy

## Purpose

Acceptance tests verify that World Notes' critical user journeys work on iOS
and Android. Coverage is measured across critical journeys, permission
boundaries, failure recovery, and platform-specific risks rather than by lines
of code.

## Separation from Store Screenshot Automation

| Area | Acceptance tests | Store screenshots |
|---|---|---|
| Maestro workspace | `maestro/acceptance/` | `maestro/screenshots/` |
| Runtime mode | `ACCEPTANCE_TEST_MODE=true` | `SCREENSHOT_MODE=true` |
| Authentication | Operates the sign-in screen | Automatically signs in a fixed user |
| Data | `npm run seed:acceptance` | `npm run seed:screenshot` |
| Primary output | JUnit, failure images, and logs | Store listing images |
| Pass criteria | Behavioral assertions | Successful capture and visual review |

Do not enable both modes at the same time. Shared subflows, if introduced,
must be limited to side-effect-free navigation. Test data and expected results
must remain separate.

`ACCEPTANCE_TEST_MODE` is active only in debug builds connected to Firebase
Emulator. It resets authentication at the start of each Flow and suppresses ad
and notification registration that could interrupt the core suite. Ads,
notifications, and purchases are covered by dedicated integration tests or
pre-release manual checks.

## Coverage Priorities

- P0: Release-blocking critical journeys. Automate the happy path and critical
  failure or recovery behavior.
- P1: Important state branches and regression cases. Automate them when they
  can run deterministically.
- P2: Low-frequency features, presentation variants, and subjective quality.
  Assign them to lower-level tests or manual review.

Do not target an acceptance-test count or code-coverage percentage. Record
whether each feature or risk is covered by Unit, Widget, Maestro, or manual
testing in [`test-catalog.md`](test-catalog.md).

## Flow Conventions

- Keep one user journey in each Flow.
- Give every filename and `name` a stable ID such as `AT-001`.
- Include `acceptance`, priority, and feature-area tags.
- Prefer Flutter Semantics IDs over visible text for selectors.
- Use `extendedWaitUntil` for state transitions instead of fixed delays.
- Assert important intermediate states, not only the final destination.
- Write generated results to `artifacts/acceptance/`; do not commit them.

## Local Execution

Start Firebase Emulator:

```bash
firebase emulators:start \
  --project world-notes-prod \
  --only auth,firestore,functions,storage
```

In another terminal, start the app on an explicit simulator or emulator:

```bash
flutter run \
  -d <device-id> \
  --dart-define=USE_FIREBASE_EMULATORS=true \
  --dart-define=ACCEPTANCE_TEST_MODE=true
```

Run the tests from a third terminal:

```bash
./scripts/run_acceptance_tests.sh
```

The runner executes the `smoke` tag by default. Override the selection when
needed:

```bash
ACCEPTANCE_TAGS=p0 ./scripts/run_acceptance_tests.sh
```

Override credentials with `ACCEPTANCE_AUTH_EMAIL` and
`ACCEPTANCE_AUTH_PASSWORD` when necessary.

## Results

Each run creates `artifacts/acceptance/<UTC timestamp>/` containing:

- `report.xml`: JUnit report for CI aggregation
- `maestro/`: failure screenshots, recordings, logs, and command metadata

CI should publish the JUnit summary and retain `maestro/` as a debugging
artifact. Changes to a tested feature and its acceptance Flow should be kept in
the same pull request.
