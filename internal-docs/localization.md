# Localization Architecture

## Supported locales

The initial release set is:

- English: `en`
- Japanese: `ja`
- Traditional Chinese: `zh_Hant`
- Simplified Chinese: `zh_Hans`
- Korean: `ko`

Use script codes for Chinese instead of region codes. This lets Flutter resolve
Traditional or Simplified Chinese correctly across regions. Planned additions
are `fr`, `de`, `it`, `es`, `pt`, `th`, `my`, and `vi`. Portuguese can be split
into `pt_BR` and `pt_PT` later if product copy diverges.

Flutter also requires `app_zh.arb` as a base fallback whenever both Chinese
script variants exist. It intentionally mirrors Simplified Chinese, but is not
an additional store-listing locale.

## Public app name

The public app name should be expressed in the primary language and script of
each store-listing locale. Keep the Flutter title, the iOS and Android home
screen label, and the App Store Connect or Google Play listing name aligned.

| Locale | Public app name |
| --- | --- |
| `en` | World Notes |
| `ja` | セカイノート |
| `zh_Hans` | 世界日记 |
| `zh_Hant` | 世界日記 |
| `ko` | 세계 일기 |

For future locales, decide the localized public name with a native-language
review before creating the store listing. Internal identifiers such as the
bundle ID, entitlement ID, product IDs, analytics keys, and repository name
remain language-neutral and must not be renamed as part of localization.

## Source of truth

- `app_en.arb` defines the complete message API, placeholders, and metadata.
- `app_ja.arb` is the semantic reference when English wording is ambiguous.
- Every other ARB must contain the same message keys as the English template.
- Generated `app_localizations*.dart` files must not be edited manually.

`required-resource-attributes: true` makes `flutter gen-l10n` reject a new
English message that has no matching `@messageKey` metadata entry. Placeholder
types belong only in the English template and must describe values passed from
Dart rather than sentence fragments.

## Key and sentence rules

- Name keys by feature and intent, for example `mapNoNotes` or
  `subscriptionTemporarilyUnavailable`.
- Put complete user-facing phrases in ARB. Do not build sentences by joining
  translated fragments in Dart.
- Keep calculations and raw domain values in Dart, then pass the result to an
  ARB placeholder.
- Keep user content, Firestore data, and screenshot seed content outside ARB.
- Add translator context in the English `@messageKey.description` when a key
  is ambiguous, visually constrained, or used for accessibility.

## Dart access and formatting

- UI code reads copy through `context.l10n` from `l10n.dart`.
- Locale-sensitive dates, relative time, and lifetime phrases belong in
  `localized_formatters.dart`.
- Labels that map domain enums to ARB messages belong in
  `presentation_labels.dart`.
- ARB owns grammar; formatter and label helpers only select a complete ARB
  message and supply its values.

## Verification

Do not add a regex-based hardcoded-string CI gate for now. Use:

1. `flutter gen-l10n` for ARB structure, metadata, and placeholder validation.
2. Unit/widget tests that load every supported locale.
3. Screenshot-mode smoke tests in each release locale.
4. Code review and an occasional manual audit for remaining UI literals.
