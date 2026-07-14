# Note Themes

## Goal

Give each note a distinct, built-in visual theme, similar to a LINE chat
theme. A theme changes the note preview bottom sheet and the note-detail
screen, while the map pin's existing `colorHex` and icon remain independent.

The first release ships five app-defined themes:

| ID | Name | Direction |
| --- | --- | --- |
| `aurora` | Aurora | Modern deep indigo with aqua and violet accents. |
| `citrus` | Citrus Pop | Warm cream, coral, orange, and teal for a playful look. |
| `botanical` | Botanical | Calm jade and leaf green on a soft natural surface. |
| `neon` | Neon Grid | Cyberpunk near-black with cyan and fuchsia highlights. |
| `editorial` | Editorial | Crisp paper-like neutral surfaces with a strong cobalt accent. |

Theme IDs are stable product identifiers. Display names, token values, and
preview artwork live in the app and can change without a data migration. The
first version deliberately does not allow custom color uploads or user-defined
themes.

## Data model

Add the required field below to `places/{placeId}`:

```text
themeId: string // one of: aurora, citrus, botanical, neon, editorial
```

`themeId` is metadata for the note surface, not map-marker styling:

- `colorHex` continues to control the map pin and is chosen at creation.
- `themeId` controls the visual language used after selecting/opening a note.
- No client compatibility fallback is provided for missing or invalid values.

`createNote` requires and validates `themeId`. `listMapPins` includes it in
its payload so the marker bottom sheet can render without fetching the entire
`places` document.

Before shipping the Flutter client, run an Admin SDK migration over every
existing `places` document to set `themeId: 'aurora'`. The migration is
idempotent and only writes documents missing the field. No legacy documents
are deliberately retained after the migration.

## Client model and palettes

Create a pure-Dart ID type in `lib/domain/entities/note_theme.dart`:

```dart
enum NoteThemeId { aurora, citrus, botanical, neon, editorial }
```

and a Flutter palette registry in `lib/core/theme/note_themes.dart`:

```dart
class NoteThemePalette {
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color primary;
  final Color onPrimary;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color positiveAccent;
  final Color dangerAccent;
  final List<Color> heroGradient;
}
```

The ID type performs strict storage parsing; invalid values are treated as a
data-contract violation. The Flutter registry owns translated display labels,
preview treatment, and colors. The colors are semantic tokens rather than raw
colors in widgets, so all themes receive the same UI behavior and contrast can
be tested centrally.

`PlaceEntity`, `PlaceModel`, `PinSummary`, and `PinSummaryModel` carry the
parsed `NoteThemeId`. At the UI boundary, derive a local `ThemeData`/
`ColorScheme` from the palette. Do not mutate the application-wide theme.

## Light and dark appearance

The app already follows the system setting through `ThemeMode.system`; note
themes must do the same. A note never stores whether it is light or dark.
`themeId` selects its visual identity, and the active app brightness selects
one of that identity's two palettes:

```dart
class NoteThemeDefinition {
  final NoteThemePalette light;
  final NoteThemePalette dark;
}
```

Resolve the palette from `Theme.of(context).brightness`, so the system setting
changes the open bottom sheet and note detail without a data write or an app
restart. The picker previews the palette appropriate to the current setting.

Every theme has a deliberate dark counterpart, including Citrus Pop,
Botanical, and Editorial; they are not simply color-inverted. Aurora becomes
deeper and more luminous, while Neon Grid remains dark in both modes but uses
a distinct dark palette with reduced glow and higher text contrast. Background
surfaces, text, outlines, chip states, CTA colors, message bubbles, and focus/
disabled states must be specified in both palettes. Body text and interactive
controls must meet WCAG AA contrast (4.5:1 for normal text) in both modes.

## Presentation behavior

### Map marker bottom sheet

`NoteMarkerBottomSheet` receives the summary's theme ID and applies the local
theme to its sheet surface, drag handle, title/subtitle, metadata chips, and
Open button. The pin avatar keeps using `colorHex`, preserving the visual
connection to the marker on the map.

### Note detail

`NoteBoxScreen` resolves the current `PlaceEntity.themeId` from its live
stream. Wrap only the note screen's scaffold subtree in the local theme. Apply
the palette to the app bar, screen background, mini-map frame, status/like
rows, floating action button, message-list background, and message bubbles.
Modal controls launched from the screen inherit the same local theme.

The image viewer remains black, and error/destructive states retain explicit
high-contrast colors. Theme colors are decorative and must never make lock,
closed, expiry, moderation, or access state ambiguous.

### Note lists

Map Notes, My Notes, and Archived Notes use the theme as a compact identity
signal, not as a full-screen treatment. Each `NoteListCard` receives the
resolved palette and uses its surface, outline, a narrow leading accent, and
selected metadata/count colors. The pin avatar continues to use `colorHex`.

Archived cards retain the same identity at reduced saturation and opacity, but
the archive label and status remain visually dominant. List backgrounds stay
application-neutral so mixed-theme lists remain scannable and accessible.

### Theme picker and authorization

Add a `Change theme` entry to the note-detail overflow menu when
`NotePermissions.canChangeTheme` is true. It opens a scroll-controlled picker
sheet with five selectable preview cards. A card shows its name, short style
description, color/gradient sample, and a selected checkmark. Selecting a
theme updates the note; the live place stream updates the detail screen and
subsequent map-sheet previews.

Changing a theme is allowed for every active note maintainer (creator and
delegated maintainers), matching the requested operational role. It is hidden
and rejected for members and visitors, and unavailable after archival. This is
intentionally broader than lock/archive permissions, which remain
creator-only.

## Write path and security

Do not add direct client writes for this field. Add a callable:

```text
setNoteTheme({ placeId, themeId })
```

The Cloud Function must require authentication and App Check, then in a
transaction:

1. read the place;
2. verify the caller with `canMaintainNote`;
3. reject missing, archived, malformed, or unsupported values;
4. update only `themeId` (an identical value is a no-op).

The existing Firestore rule for `/places/{placeId}` continues to permit only
the narrowly defined close/re-open client transition, thereby denying direct
theme changes. This avoids broadening rules for a cosmetic field.

## Creation behavior

The initial delivery should add the same compact picker to note creation,
preselected to `aurora`, so new notes are purposeful from the start. Forking
an archived note copies its required `themeId`.

## Rollout and migration

Because this is still in development, treat the field as a strict schema
change rather than a backward-compatible rollout:

1. Deploy the server changes that validate/write `themeId` and return it from
   `listMapPins`; do not publish the new Flutter build yet.
2. Run `functions/src/scripts/backfillNoteThemes.ts` with Admin SDK credentials
   to set `aurora` on documents that predate the schema.
3. Verify there are no missing or unsupported values in `places`.
4. Release the Flutter build with strict model parsing.

The migration script reports scanned, changed, skipped, and invalid-document
counts, performs bounded batched writes, and is safe to rerun. Development
seed data must set a valid `themeId` explicitly.

## Implementation slices

1. Add pure-Dart theme IDs/registry and strict entity/model handling, with
   unit tests for every valid ID and rejected absent/invalid values.
2. Carry `themeId` through create, Firestore, map-pin callable, and summary
   models; add `setNoteTheme` to the repository and function exports.
3. Extend `NotePermissions`, add the picker, and apply the local palette to
   the bottom sheet, note detail screen, and compact list cards.
4. Add creation/fork selection, localization strings, and widget tests for
   visual selection, maintainer visibility, non-maintainer hiding, and
   archived-card treatment.
5. Add the Admin SDK backfill script and seed-data field, then test light and
   dark palettes (including contrast) in widget tests.
6. Run Flutter tests/analyzer and Functions type/lint tests; deploy rules only
   if their existing denial behavior is changed (the proposed design does not
   require a rules change).

## Acceptance criteria

- Each of the five IDs has a visually distinct, readable preview and detail
  appearance in both light and dark mode.
- Every stored note has one valid `themeId` before the Flutter client with this
  feature is released.
- The bottom sheet and detail screen show the same theme for the same note.
- Map Notes, My Notes, and Archived Notes present the same theme as a compact
  card accent without changing the map pin color.
- Maintainers can change themes from detail; members and visitors cannot.
- Direct Firestore clients cannot change `themeId`.
- Pin color and icon remain unchanged when a note theme changes.
