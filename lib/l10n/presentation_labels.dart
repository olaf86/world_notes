import '../domain/entities/note_list_sort.dart';
import 'app_locale.dart';
import 'app_localizations.dart';

/// Localized labels for app-language choices. Language names intentionally use
/// their autonyms in every ARB so users can recover after selecting a language
/// they do not read.
extension AppLanguagePreferencePresentationLabel on AppLanguagePreference {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AppLanguagePreference.system => l10n.settingsLanguageSystem,
    AppLanguagePreference.english => l10n.settingsLanguageEnglish,
    AppLanguagePreference.japanese => l10n.settingsLanguageJapanese,
    AppLanguagePreference.korean => l10n.settingsLanguageKorean,
    AppLanguagePreference.simplifiedChinese =>
      l10n.settingsLanguageSimplifiedChinese,
    AppLanguagePreference.traditionalChinese =>
      l10n.settingsLanguageTraditionalChinese,
  };

  String? localizedDescription(AppLocalizations l10n) => switch (this) {
    AppLanguagePreference.system => l10n.settingsLanguageSystemDescription,
    _ => null,
  };
}

/// Localized labels for domain values displayed by the presentation layer.
extension NoteListSortPresentationLabel on NoteListSort {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    NoteListSort.distance => l10n.sortDistance,
    NoteListSort.lastActivity => l10n.sortLastActivity,
    NoteListSort.newest => l10n.sortNewest,
    NoteListSort.expiresSoonest => l10n.sortExpiresSoon,
    NoteListSort.mostLiked => l10n.sortMostLiked,
    NoteListSort.archivedNewest => l10n.sortArchivedNewest,
    NoteListSort.archivedOldest => l10n.sortArchivedOldest,
  };
}
