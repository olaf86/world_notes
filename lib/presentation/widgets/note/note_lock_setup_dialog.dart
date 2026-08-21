import 'package:flutter/material.dart';

import '../../../core/utils/password_util.dart';
import '../../../core/utils/pattern_lock_util.dart';
import '../../../domain/entities/place_entity.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_labels.dart';
import '../pattern_lock/pattern_lock_input.dart';

class NoteLockSetupValue {
  final NoteLockType lockType;
  final String secret;
  final String? lockHint;

  const NoteLockSetupValue({
    required this.lockType,
    required this.secret,
    this.lockHint,
  });
}

enum NoteLockSetupMethod { password, pattern }

extension NoteLockSetupMethodX on NoteLockSetupMethod {
  NoteLockType get noteLockType => switch (this) {
    NoteLockSetupMethod.password => NoteLockType.password,
    NoteLockSetupMethod.pattern => NoteLockType.pattern,
  };

  static NoteLockSetupMethod fromLockType(NoteLockType? lockType) =>
      switch (lockType) {
        NoteLockType.pattern => NoteLockSetupMethod.pattern,
        _ => NoteLockSetupMethod.password,
      };
}

class NoteLockSetupDialog extends StatefulWidget {
  final String title;
  final String? submitLabel;
  final NoteLockType? initialLockType;
  final String? initialHint;
  final VoidCallback onPatternTooLong;
  final Future<String?> Function(NoteLockSetupValue value)? onSubmit;

  const NoteLockSetupDialog({
    super.key,
    required this.title,
    this.submitLabel,
    this.initialLockType,
    this.initialHint,
    required this.onPatternTooLong,
    this.onSubmit,
  });

  @override
  State<NoteLockSetupDialog> createState() => _NoteLockSetupDialogState();
}

class _NoteLockSetupDialogState extends State<NoteLockSetupDialog> {
  late NoteLockSetupMethod _method;
  late final TextEditingController _hintController;
  var _password = '';
  var _passwordConfirmation = '';
  List<int> _pattern = const [];
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _method = NoteLockSetupMethodX.fromLockType(widget.initialLockType);
    _hintController = TextEditingController(text: widget.initialHint ?? '');
  }

  @override
  void dispose() {
    _hintController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final validation = switch (_method) {
      NoteLockSetupMethod.password => PasswordUtil.confirmationValidationError(
        password: _password,
        confirmation: _passwordConfirmation,
      )?.localizedLabel(context.l10n),
      NoteLockSetupMethod.pattern => PatternLockUtil.validationError(
        _pattern,
      )?.localizedLabel(context.l10n),
    };
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    final secret = switch (_method) {
      NoteLockSetupMethod.password => _password,
      NoteLockSetupMethod.pattern => PatternLockUtil.encode(_pattern),
    };
    final trimmedHint = _hintController.text.trim();
    final value = NoteLockSetupValue(
      lockType: _method.noteLockType,
      secret: secret,
      lockHint: trimmedHint.isEmpty ? null : trimmedHint,
    );
    final onSubmit = widget.onSubmit;
    if (onSubmit == null) {
      Navigator.pop(context, value);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await onSubmit(value);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, value);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<NoteLockSetupMethod>(
              segments: [
                ButtonSegment(
                  value: NoteLockSetupMethod.password,
                  icon: const Icon(Icons.password_outlined),
                  label: Text(l10n.passwordLabel),
                ),
                ButtonSegment(
                  value: NoteLockSetupMethod.pattern,
                  icon: const Icon(Icons.grid_3x3),
                  label: Text(l10n.patternLabel),
                ),
              ],
              selected: {_method},
              onSelectionChanged: _busy
                  ? null
                  : (selected) {
                      setState(() {
                        _method = selected.single;
                        _password = '';
                        _passwordConfirmation = '';
                        _pattern = const [];
                        _error = null;
                      });
                    },
            ),
            const SizedBox(height: 12),
            if (_method == NoteLockSetupMethod.password)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PasswordLockInput(
                    enabled: !_busy,
                    labelText: l10n.passwordLabel,
                    textInputAction: TextInputAction.next,
                    onChanged: (value) {
                      setState(() {
                        _password = value;
                        _error = null;
                      });
                    },
                    onSubmitted: () => FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  PasswordLockInput(
                    enabled: !_busy,
                    labelText: l10n.confirmPasswordLabel,
                    autofocus: false,
                    onChanged: (value) {
                      setState(() {
                        _passwordConfirmation = value;
                        _error = null;
                      });
                    },
                    onSubmitted: _submit,
                  ),
                ],
              )
            else ...[
              Text(l10n.patternSetupInstruction),
              const SizedBox(height: 12),
              PatternLockInputWithClear(
                enabled: !_busy,
                size: 248,
                onChanged: (path) {
                  setState(() {
                    _pattern = path;
                    _error = null;
                  });
                },
                onTooLong: widget.onPatternTooLong,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _hintController,
              enabled: !_busy,
              maxLength: 140,
              decoration: InputDecoration(
                labelText: l10n.lockHintOptional,
                counterText: '',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.submitLabel ?? l10n.commonSave),
        ),
      ],
    );
  }
}

class PasswordLockInput extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final String? labelText;
  final TextInputAction textInputAction;
  final bool enabled;
  final bool autofocus;

  const PasswordLockInput({
    super.key,
    required this.onChanged,
    required this.onSubmitted,
    this.labelText,
    this.textInputAction = TextInputAction.done,
    this.enabled = true,
    this.autofocus = true,
  });

  @override
  State<PasswordLockInput> createState() => _PasswordLockInputState();
}

class _PasswordLockInputState extends State<PasswordLockInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      maxLength: PasswordUtil.maxLength,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSubmitted(),
      decoration: InputDecoration(
        labelText: widget.labelText ?? context.l10n.passwordLabel,
        counterText: '',
      ),
    );
  }
}

class PatternLockInputWithClear extends StatefulWidget {
  final ValueChanged<List<int>> onChanged;
  final ValueChanged<List<int>>? onCompleted;
  final VoidCallback? onTooLong;
  final bool enabled;
  final double size;

  const PatternLockInputWithClear({
    super.key,
    required this.onChanged,
    this.onCompleted,
    this.onTooLong,
    this.enabled = true,
    this.size = 280,
  });

  @override
  State<PatternLockInputWithClear> createState() =>
      _PatternLockInputWithClearState();
}

class _PatternLockInputWithClearState extends State<PatternLockInputWithClear> {
  var _inputKey = UniqueKey();
  var _hasPattern = false;

  void _handleChanged(List<int> path) {
    setState(() => _hasPattern = path.isNotEmpty);
    widget.onChanged(path);
  }

  void _clear() {
    setState(() {
      _inputKey = UniqueKey();
      _hasPattern = false;
    });
    widget.onChanged(const []);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        IgnorePointer(
          ignoring: !widget.enabled,
          child: PatternLockInput(
            key: _inputKey,
            size: widget.size,
            onChanged: _handleChanged,
            onCompleted: widget.onCompleted,
            onTooLong: widget.onTooLong,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.enabled && _hasPattern ? _clear : null,
            icon: const Icon(Icons.backspace_outlined),
            label: Text(l10n.clearAction),
          ),
        ),
      ],
    );
  }
}
