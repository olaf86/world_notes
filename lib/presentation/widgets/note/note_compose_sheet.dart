import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';

/// Modal bottom sheet for composing a new message.
///
/// Why a bottom sheet rather than a pushed full-screen route?
///
/// `showModalBottomSheet` returns a `ModalBottomSheetRoute` which extends
/// `PopupRoute` — the same route family used by `showDialog`.  PopupRoutes
/// never offstage the route below them (no `Offstage(offstage:true)` is
/// applied to NoteBoxScreen), so the unbounded `BoxConstraints()` /
/// `computeDryBaseline` chain that produced the '!semantics.parentDataDirty'
/// loop with `Navigator.push(PageRouteBuilder)` cannot happen here.
///
/// See:
///   * https://github.com/flutter/flutter/issues/169214
///   * https://github.com/flutter/flutter/pull/171250
class NoteComposeSheet extends ConsumerStatefulWidget {
  final String placeId;
  final List<int>? initialImageBytes;
  final String? initialImageName;

  const NoteComposeSheet({
    super.key,
    required this.placeId,
    this.initialImageBytes,
    this.initialImageName,
  });

  @override
  ConsumerState<NoteComposeSheet> createState() => _NoteComposeSheetState();
}

class _NoteComposeSheetState extends ConsumerState<NoteComposeSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  List<int>? _imageBytes;
  String? _imageName;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _imageBytes = widget.initialImageBytes;
    _imageName = widget.initialImageName;
    _controller.addListener(_onTextChanged);
    // Defer focus to after the sheet's slide-up settles so the keyboard
    // doesn't race the bottom sheet animation for viewInsets.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _controller.text.trim().isNotEmpty || _imageBytes != null;

  Future<void> _submit() async {
    if (!_hasContent || _isSending) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isSending = true);
    try {
      await ref.read(messageRepositoryProvider).sendMessage(
            placeId: widget.placeId,
            content: _controller.text.trim(),
            userId: user.id,
            userName: user.name,
            userPhotoUrl: user.photoUrl,
            imageBytes: _imageBytes,
            imageName: _imageName,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  void _removeImage() => setState(() {
        _imageBytes = null;
        _imageName = null;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _imageBytes;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final mediaSize = MediaQuery.sizeOf(context);

    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        // Cap the sheet at 90 % of screen height (X/Instagram style).
        height: mediaSize.height * 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header: close · title · send ────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel',
                    onPressed: _isSending
                        ? null
                        : () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'New message',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (_isSending)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: _hasContent ? _submit : null,
                      child: const Text('Send'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Text field — expands to fill remaining space ────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Write a message…',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),

            // ── Image attachment preview ──────────────────────────────────
            if (bytes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        Uint8List.fromList(bytes),
                        width: double.infinity,
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: GestureDetector(
                        onTap: _isSending ? null : _removeImage,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
