import 'package:flutter/material.dart';

import '../../../core/theme/note_themes.dart';
import '../../../domain/entities/note_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_labels.dart';

class NoteThemePicker extends StatelessWidget {
  final NoteThemeId selected;
  final ValueChanged<NoteThemeId> onChanged;

  const NoteThemePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = NoteThemes.paletteOf(context, selected);

    return ListTile(
      key: const ValueKey('note-theme-picker-tile'),
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: palette.previewGradient,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.colorScheme.outlineVariant),
        ),
      ),
      title: Text(
        context.l10n.noteThemeLabel,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(selected.localizedLabel(context.l10n)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final themeId = await showNoteThemePicker(
          context: context,
          selected: selected,
        );
        if (themeId != null && themeId != selected) onChanged(themeId);
      },
    );
  }
}

Future<NoteThemeId?> showNoteThemePicker({
  required BuildContext context,
  required NoteThemeId selected,
  String? title,
  String? description,
  ThemeData? sheetTheme,
}) {
  return showModalBottomSheet<NoteThemeId>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final content = SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title ?? sheetContext.l10n.noteThemeLabel,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              if (description != null) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              _NoteThemeOptions(selected: selected),
            ],
          ),
        ),
      );
      return sheetTheme == null
          ? content
          : Theme(data: sheetTheme, child: content);
    },
  );
}

class _NoteThemeOptions extends StatelessWidget {
  final NoteThemeId selected;

  const _NoteThemeOptions({required this.selected});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Column(
      children: NoteThemes.all.map((definition) {
        final palette = definition.paletteFor(brightness);
        final isSelected = definition.id == selected;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: palette.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: isSelected
                    ? palette.colorScheme.primary
                    : palette.colorScheme.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: InkWell(
              key: ValueKey('note-theme-option-${definition.id.name}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.pop(context, definition.id),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: palette.previewGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              color: palette.colorScheme.onSurface,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            definition.id.localizedLabel(context.l10n),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: palette.colorScheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            definition.id.localizedDescription(context.l10n),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: palette.colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
