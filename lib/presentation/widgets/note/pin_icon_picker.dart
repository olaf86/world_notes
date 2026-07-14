import 'package:flutter/material.dart';

/// A map-pin icon option that can be persisted using [id].
class PinIconOption {
  final String id;
  final IconData icon;

  const PinIconOption(this.id, this.icon);
}

/// Compact icon selection with an expandable set of additional choices.
class PinIconPicker extends StatelessWidget {
  final List<PinIconOption> icons;
  final String selected;
  final Color selectedColor;
  final bool showMore;
  final int inlineOptionCount;
  final ValueChanged<String> onSelected;
  final VoidCallback onToggleMore;

  const PinIconPicker({
    super.key,
    required this.icons,
    required this.selected,
    required this.selectedColor,
    required this.showMore,
    required this.inlineOptionCount,
    required this.onSelected,
    required this.onToggleMore,
  });

  @override
  Widget build(BuildContext context) {
    final inlineIcons = icons.take(inlineOptionCount).toList();
    if (!inlineIcons.any((icon) => icon.id == selected) &&
        inlineIcons.isNotEmpty) {
      inlineIcons[inlineIcons.length - 1] = icons.firstWhere(
        (icon) => icon.id == selected,
        orElse: () => inlineIcons.last,
      );
    }
    final additionalIcons = icons
        .where((icon) => !inlineIcons.contains(icon))
        .toList();

    return Column(
      children: [
        Row(
          children: [
            for (var index = 0; index < inlineIcons.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              _IconChoice(
                icon: inlineIcons[index],
                selected: selected == inlineIcons[index].id,
                selectedColor: selectedColor,
                onTap: () => onSelected(inlineIcons[index].id),
              ),
            ],
            const Spacer(),
            IconButton(
              tooltip: showMore ? 'Show fewer icons' : 'Show more icons',
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
                children: additionalIcons
                    .map(
                      (icon) => _IconChoice(
                        icon: icon,
                        selected: selected == icon.id,
                        selectedColor: selectedColor,
                        onTap: () => onSelected(icon.id),
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

class _IconChoice extends StatelessWidget {
  final PinIconOption icon;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: icon.id,
      child: Semantics(
        button: true,
        selected: selected,
        label: icon.id,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: selected
                  ? selectedColor
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon.icon,
              size: 20,
              color: selected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
