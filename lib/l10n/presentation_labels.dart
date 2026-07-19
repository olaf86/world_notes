import '../domain/entities/note_list_sort.dart';
import 'app_localizations.dart';

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
