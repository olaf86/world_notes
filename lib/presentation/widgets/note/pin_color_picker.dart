import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';

/// Compact color selection with an expandable set of additional choices.
class PinColorPicker extends StatelessWidget {
  final List<Color> colors;
  final Color selected;
  final bool showMore;
  final int inlineOptionCount;
  final ValueChanged<Color> onSelected;
  final VoidCallback onToggleMore;

  const PinColorPicker({
    super.key,
    required this.colors,
    required this.selected,
    required this.showMore,
    required this.inlineOptionCount,
    required this.onSelected,
    required this.onToggleMore,
  });

  @override
  Widget build(BuildContext context) {
    final inlineColors = colors.take(inlineOptionCount).toList();
    if (!inlineColors.contains(selected) && inlineColors.isNotEmpty) {
      inlineColors[inlineColors.length - 1] = selected;
    }
    final additionalColors = colors
        .where((color) => !inlineColors.contains(color))
        .toList();

    return Column(
      children: [
        Row(
          children: [
            for (var index = 0; index < inlineColors.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              _ColorChoice(
                color: inlineColors[index],
                selected: selected == inlineColors[index],
                onTap: () => onSelected(inlineColors[index]),
              ),
            ],
            const Spacer(),
            IconButton(
              tooltip: showMore
                  ? context.l10n.showFewerColors
                  : context.l10n.showMoreColors,
              onPressed: onToggleMore,
              icon: Icon(showMore ? Icons.expand_less : Icons.expand_more),
            ),
          ],
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: showMore
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: additionalColors
                    .map(
                      (color) => _ColorChoice(
                        color: color,
                        selected: selected == color,
                        onTap: () => onSelected(color),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorChoice extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorLabel = _colorLabel(context, color);
    return Tooltip(
      message: colorLabel,
      child: Semantics(
        button: true,
        selected: selected,
        label: colorLabel,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 3,
                    )
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        ),
      ),
    );
  }
}

String _colorLabel(BuildContext context, Color color) {
  final l10n = context.l10n;
  if (color == Colors.green) return l10n.colorGreen;
  if (color == Colors.blue) return l10n.colorBlue;
  if (color == Colors.red) return l10n.colorRed;
  if (color == Colors.orange) return l10n.colorOrange;
  if (color == Colors.purple) return l10n.colorPurple;
  if (color == Colors.teal) return l10n.colorTeal;
  if (color == Colors.pink) return l10n.colorPink;
  if (color == Colors.brown) return l10n.colorBrown;
  if (color == Colors.indigo) return l10n.colorIndigo;
  if (color == Colors.cyan) return l10n.colorCyan;
  if (color == Colors.lime) return l10n.colorLime;
  if (color == Colors.amber) return l10n.colorAmber;
  if (color == Colors.deepOrange) return l10n.colorDeepOrange;
  if (color == Colors.blueGrey) return l10n.colorBlueGrey;
  return l10n.pinColorLabel;
}
