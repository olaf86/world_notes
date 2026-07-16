import 'package:flutter/material.dart';

import '../../../core/theme/note_themes.dart';
import '../../../domain/entities/note_theme.dart';

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
              borderRadius: BorderRadius.circular(14),
              onTap: () => onChanged(definition.id),
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
                            definition.name,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: palette.colorScheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            definition.description,
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
