# Note Themes

## Goal

Give each note a distinct, built-in visual theme, similar to a LINE chat
theme. A theme changes the note preview bottom sheet and the note-detail
screen, while the map pin's existing `colorHex` and icon remain independent.

The first release ships six app-defined themes:

| ID | Name | Direction |
| --- | --- | --- |
| `standard` | Standard | The calm, familiar World Notes appearance. Default. |
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
themeId: string // one of: standard, aurora, citrus, botanical, neon, editorial
```

`themeId` is metadata for the note surface, not map-marker styling:

- `colorHex` continues to control the map pin and is chosen at creation.
- `themeId` controls the visual language used after selecting/opening a note.
- No client compatibility fallback is provided for missing or invalid values.

`createNote` requires and validates `themeId`. `listMapPins` includes it in
its payload so the marker bottom sheet can render without fetching the entire
`places` document.

## Client model and palettes

Create a pure-Dart ID type in `lib/domain/entities/note_theme.dart`:

```dart
enum NoteThemeId { standard, aurora, citrus, botanical, neon, editorial }
```

and a Flutter palette registry in `lib/core/theme/note_themes.dart`:

```dart
class NoteThemePalette {
  final ColorScheme colorScheme;
  final List<Color> heroGradient;

  LinearGradient get pageGradient;
  LinearGradient cardGradient({required bool isArchived});
  LinearGradient get previewGradient;
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
The screen background uses a broad, low-frequency diagonal gradient rather
than a flat fill. Content surfaces may remain slightly translucent so the
theme is present throughout the page without reducing text readability. Modal
controls launched from the screen inherit the same local theme.

The image viewer remains black, and error/destructive states retain explicit
high-contrast colors. Theme colors are decorative and must never make lock,
closed, expiry, moderation, or access state ambiguous.

### Note lists

Map Notes, My Notes, and Archived Notes use the theme as a compact identity
signal, not as a full-screen treatment. Each `NoteListCard` receives the
resolved palette and uses a quiet gradient surface, outline, and selected
metadata/count colors. A separate leading theme stripe is deliberately not
used: the card background itself is the identity signal, while the pin avatar
continues to use `colorHex`.

Archived cards retain the same identity at reduced saturation and opacity, but
the archive label and status remain visually dominant. List backgrounds stay
application-neutral so mixed-theme lists remain scannable and accessible.

Gradient intensity follows the amount of space available. The full detail
page uses the broadest and gentlest treatment, list cards blend their theme
colors more heavily toward the local surface, and bottom-sheet/picker previews
use the clearest theme colors. This keeps mixed lists calm while making focused
theme exploration feel expressive. All three treatments resolve distinct
light and dark palettes.

### Theme picker and authorization

Add a `Change theme` entry to the note-detail overflow menu when
`NotePermissions.canChangeTheme` is true. It opens a scroll-controlled picker
sheet with six selectable preview cards. A card shows its name, short style
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
preselected to `standard`, so new notes begin with the familiar app appearance.
Forking
an archived note copies its required `themeId`.

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
5. Add the theme field to development seed data, then test light and dark
   palettes (including contrast) in widget tests.
6. Run Flutter tests/analyzer and Functions type/lint tests; deploy rules only
   if their existing denial behavior is changed (the proposed design does not
   require a rules change).

## Acceptance criteria

- Each of the six IDs has a visually distinct, readable preview and detail
  appearance in both light and dark mode.
- Every stored note has one valid `themeId`.
- The bottom sheet and detail screen show the same theme for the same note.
- Map Notes, My Notes, and Archived Notes present the same theme as a compact
  gradient card surface without changing the map pin color or adding a theme
  stripe.
- Maintainers can change themes from detail; members and visitors cannot.
- Direct Firestore clients cannot change `themeId`.
- Pin color and icon remain unchanged when a note theme changes.
