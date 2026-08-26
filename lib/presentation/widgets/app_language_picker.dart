import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/l10n.dart';
import '../../l10n/presentation_labels.dart';
import '../providers/providers.dart';

/// A language picker that is available before account setup is complete.
///
/// Language names are displayed as autonyms so the picker remains usable even
/// when the currently selected language is unfamiliar to the user.
class AppLanguagePickerButton extends ConsumerStatefulWidget {
  const AppLanguagePickerButton({super.key, this.showSelectedLanguage = true});

  final bool showSelectedLanguage;

  @override
  ConsumerState<AppLanguagePickerButton> createState() =>
      _AppLanguagePickerButtonState();
}

class _AppLanguagePickerButtonState
    extends ConsumerState<AppLanguagePickerButton> {
  bool _updating = false;

  Future<void> _showPicker() async {
    if (_updating) return;
    final selected = ref.read(appLanguagePreferenceProvider);
    final preference = await showModalBottomSheet<AppLanguagePreference>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    l10n.settingsLanguageTitle,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                RadioGroup<AppLanguagePreference>(
                  groupValue: selected,
                  onChanged: (value) {
                    if (value != null) Navigator.pop(sheetContext, value);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: AppLanguagePreference.values.map((preference) {
                      final description = preference.localizedDescription(l10n);
                      return RadioListTile<AppLanguagePreference>(
                        value: preference,
                        title: Text(preference.localizedLabel(l10n)),
                        subtitle: description == null
                            ? null
                            : Text(description),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (preference == null || preference == selected) return;

    setState(() => _updating = true);
    try {
      await ref
          .read(appLanguagePreferenceProvider.notifier)
          .setPreference(preference);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsLanguageUpdateFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = ref.watch(appLanguagePreferenceProvider);
    final onPressed = _updating ? null : _showPicker;

    if (!widget.showSelectedLanguage) {
      return IconButton(
        key: const ValueKey('language-picker-button'),
        onPressed: onPressed,
        tooltip: l10n.settingsLanguageTitle,
        icon: _updating
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.language_outlined),
      );
    }

    return TextButton.icon(
      key: const ValueKey('language-picker-button'),
      onPressed: onPressed,
      icon: _updating
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.language_outlined),
      label: Text(selected.localizedLabel(l10n)),
    );
  }
}
