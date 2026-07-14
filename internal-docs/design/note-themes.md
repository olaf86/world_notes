# Note Themes

## Goal

Give each note a distinct, built-in visual theme, similar to a LINE chat
theme. A theme changes the note preview bottom sheet and the note-detail
screen, while the map pin's existing `colorHex` and icon remain independent.

The first release ships five app-defined themes:

| ID | Name | Direction |
| --- | --- | --- |
| `aurora` | Aurora | Modern deep indigo with aqua and violet accents. Default. |
| `citrus` | Citrus Pop | Warm cream, coral, orange, and teal for a playful look. |
| `botanical` | Botanical | Calm jade and leaf green on a soft natural surface. |
| `neon` | Neon Grid | Cyberpunk near-black with cyan and fuchsia highlights. |
| `editorial` | Editorial | Crisp paper-like neutral surfaces with a strong cobalt accent. |

Theme IDs are stable product identifiers. Display names, token values, and
preview artwork live in the app and can change without a Firestore migration.
The first version deliberately does not allow custom color uploads or
user-defined themes.

## Data model

Add the optional field below to `places/{placeId}`:

```text
themeId: string // one of the built-in IDs; `aurora` when absent
```

`themeId` is metadata for the note surface, not map-marker styling:

- `colorHex` continues to control the map pin and is chosen at creation.
- `themeId` controls the visual language used after selecting/opening a note.
- Existing documents without `themeId` resolve to `aurora` in every client and
  do not require backfilling.

The `createNote` callable writes `themeId`, defaulting to `aurora` when an
older client omits it. `listMapPins` includes it in its payload so the marker
bottom sheet can render without fetching the entire `places` document.

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

The ID type exposes safe storage parsing and a default fallback for unknown or
removed IDs. The Flutter registry owns translated display labels, preview
treatment, and colors. The colors are semantic tokens rather than raw colors
in widgets, so all themes receive the same UI behavior and contrast can be
tested centrally.

`PlaceEntity`, `PlaceModel`, `PinSummary`, and `PinSummaryModel` carry the
parsed `NoteThemeId`. At the UI boundary, derive a local `ThemeData`/
`ColorScheme` from the palette. Do not mutate the application-wide theme.

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

## Creation and legacy behavior

The initial delivery should add the same compact picker to note creation,
defaulted to `aurora`, so new notes are purposeful from the start. Forking an
archived note copies its `themeId`; a legacy source resolves to `aurora`.

The server default and client fallback make rollout safe in either deployment
order:

- old app + new backend: new notes receive `aurora`;
- new app + old legacy notes: absent `themeId` displays as `aurora`;
- unsupported stored ID: client displays `aurora`, while the callable refuses
  any new unsupported selection.

## Implementation slices

1. Add pure-Dart theme IDs/registry and entity/model fallback handling, with
   unit tests for known, absent, and invalid values.
2. Carry `themeId` through create, Firestore, map-pin callable, and summary
   models; add `setNoteTheme` to the repository and function exports.
3. Extend `NotePermissions`, add the picker, and apply the local palette to
   the bottom sheet and note detail screen.
4. Add creation/fork selection, localization strings, and widget tests for
   visual selection, maintainer visibility, and non-maintainer hiding.
5. Run Flutter tests/analyzer and Functions type/lint tests; deploy rules only
   if their existing denial behavior is changed (the proposed design does not
   require a rules change).

## Acceptance criteria

- Each of the five IDs has a visually distinct, readable preview and detail
  appearance.
- A legacy or malformed stored ID never crashes the map sheet or note detail.
- The bottom sheet and detail screen show the same theme for the same note.
- Maintainers can change themes from detail; members and visitors cannot.
- Direct Firestore clients cannot change `themeId`.
- Pin color and icon remain unchanged when a note theme changes.
