import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';

/// Full-screen message composition screen.
///
/// Pushed from [NoteBoxScreen] either for a plain-text post or with an
/// image pre-loaded when the user tapped the photo FAB.  Composing in its
/// own route gives a clean text-editing context and sidesteps the keyboard /
/// layout assertion issues that arise when editing inside a Scaffold that is
/// also managing a ListView and a banner ad.
class NoteComposeScreen extends ConsumerStatefulWidget {
  final String placeId;
  final String placeTitle;

  /// Optional image selected before opening this screen.
  final List<int>? initialImageBytes;
  final String? initialImageName;

  const NoteComposeScreen({
    super.key,
    required this.placeId,
    required this.placeTitle,
    this.initialImageBytes,
    this.initialImageName,
  });

  @override
  ConsumerState<NoteComposeScreen> createState() => _NoteComposeScreenState();
}

class _NoteComposeScreenState extends ConsumerState<NoteComposeScreen> {
  final _controller = TextEditingController();

  List<int>? _imageBytes;
  String? _imageName;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _imageBytes = widget.initialImageBytes;
    _imageName = widget.initialImageName;
    // Rebuild the Send button whenever the text changes.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _controller.text.trim().isNotEmpty || _imageBytes != null;

  // ── Submit ────────────────────────────────────────────────────────────────

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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _imageBytes;

    return Scaffold(
      appBar: AppBar(
        // CloseButton shows an "×" — conventional for modal compose screens.
        leading: const CloseButton(),
        title: const Text('New message'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isSending
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton(
                    onPressed: _hasContent ? _submit : null,
                    child: const Text('Send'),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Text field — expands to fill the available space ─────────────
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              maxLines: null,
              expands: true,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: 'Write a message…',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                border: InputBorder.none,
              ),
            ),
          ),

          // ── Image attachment preview ──────────────────────────────────────
          if (bytes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      Uint8List.fromList(bytes),
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                  // Remove button
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: GestureDetector(
                      onTap: _removeImage,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: theme.colorScheme.onInverseSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
