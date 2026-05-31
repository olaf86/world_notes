import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/providers.dart';

/// Full-screen "new message" composer rendered as an **overlay inside
/// NoteBoxScreen**, not as a separate Navigator route.
///
/// Why an overlay rather than a Route push?
///
/// Every attempt to present the composer through a Navigator route — whether
/// `Navigator.push` (PageRoute), `showModalBottomSheet`, `showDialog` (which
/// only works as a small AlertDialog), or wrapping in a `ShellRoute` — runs
/// into Flutter's `!semantics.parentDataDirty` debug loop on this screen.
/// The trigger is the `BlockSemantics` widget inside `ModalBarrier`, which
/// every modal route includes, combined with NoteBoxScreen's render tree
/// (StatefulShellRoute → IndexedStack → AnimatedSize banner → Scaffold).
///
/// By replacing the route push with a state-flag-driven overlay rendered in
/// NoteBoxScreen's own widget tree, we:
///   * add no new ModalBarrier / BlockSemantics layer,
///   * do not offstage NoteBoxScreen,
///   * still get an X / Twitter-style slide-up animation (driven by an
///     `AnimationController` in NoteBoxScreen, wrapped in `SlideTransition`).
///
/// This widget is intentionally a `Material` + `Column` — no `Scaffold` —
/// because nesting another `Scaffold` inside NoteBoxScreen's `Scaffold`
/// nests `_FloatingActionButtonScope`, `ScaffoldMessenger`, etc., which the
/// earlier `MessageCreationScreen` attempt did, breaking AppBar layout.
class MessageCreationOverlay extends ConsumerStatefulWidget {
  final String placeId;
  final VoidCallback onClose;

  const MessageCreationOverlay({
    super.key,
    required this.placeId,
    required this.onClose,
  });

  @override
  ConsumerState<MessageCreationOverlay> createState() =>
      _MessageCreationOverlayState();
}

class _MessageCreationOverlayState
    extends ConsumerState<MessageCreationOverlay> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();

  List<int>? _imageBytes;
  String? _imageName;
  bool _isSending = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    // Defer keyboard focus until after the parent's slide-up animation
    // settles to avoid viewInsets racing the layout pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _controller.text.trim().isNotEmpty || _imageBytes != null;

  // ── Image picking ─────────────────────────────────────────────────────────

  // Maximum accepted byte size after picker-side compression (5 MB).
  static const _maxImageBytes = 5 * 1024 * 1024;

  Future<void> _pickImage(ImageSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      // imageQuality + maxWidth/maxHeight compress the image on-device via
      // the platform image_picker plugin before we ever read the bytes.
      // This keeps memory usage low and avoids uploading unnecessarily large
      // files without requiring a separate compression package.
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;

      // Safety check: reject if the image is still above the size limit
      // (e.g. an unusual format that the picker doesn't compress well).
      if (bytes.length > _maxImageBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image is too large (max 5 MB). Please choose a smaller image.'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      setState(() {
        _imageBytes = bytes;
        _imageName = file.name;
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removeImage() => setState(() {
        _imageBytes = null;
        _imageName = null;
      });

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
      if (mounted) widget.onClose();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      final message = _imageBytes != null
          ? 'Failed to upload image. '
              'Check that Firebase Storage is enabled and security rules allow writes.\n$e'
          : 'Failed to send: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _imageBytes;

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            _Header(
              isSending: _isSending,
              canSend: _hasContent,
              onClose: widget.onClose,
              onSend: _submit,
            ),
            const Divider(height: 1),

            // Text editor — fills the available vertical space.
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
                  style: theme.textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: "What's happening at this place?",
                    // Remove Material 3's default filled look (grey tinted
                    // background + rounded corners).  The composer lives
                    // inside a plain white/surface Material already.
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),

            // Image attachment preview (if any).
            if (bytes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _ImagePreview(
                  bytes: bytes,
                  onRemove: _removeImage,
                ),
              ),

            const Divider(height: 1),

            // Twitter-style attachment toolbar pinned above the keyboard.
            _AttachmentToolbar(
              picking: _picking,
              onPickGallery: () => _pickImage(ImageSource.gallery),
              onPickCamera: () => _pickImage(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — Close button · Title · Send button
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final bool isSending;
  final bool canSend;
  final VoidCallback onClose;
  final VoidCallback onSend;

  const _Header({
    required this.isSending,
    required this.canSend,
    required this.onClose,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: isSending ? null : onClose,
          ),
          Expanded(
            child: Text(
              'New message',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: isSending
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: canSend ? onSend : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 36),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Send'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Image preview with remove button
// ---------------------------------------------------------------------------

class _ImagePreview extends StatelessWidget {
  final List<int> bytes;
  final VoidCallback onRemove;

  const _ImagePreview({required this.bytes, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            Uint8List.fromList(bytes),
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: GestureDetector(
            onTap: onRemove,
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
    );
  }
}

// ---------------------------------------------------------------------------
// Attachment toolbar — Twitter-style icon row above the keyboard
// ---------------------------------------------------------------------------

class _AttachmentToolbar extends StatelessWidget {
  final bool picking;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;

  const _AttachmentToolbar({
    required this.picking,
    required this.onPickGallery,
    required this.onPickCamera,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Choose from library',
            icon: const Icon(Icons.image_outlined),
            color: theme.colorScheme.primary,
            onPressed: picking ? null : onPickGallery,
          ),
          IconButton(
            tooltip: 'Take a photo',
            icon: const Icon(Icons.camera_alt_outlined),
            color: theme.colorScheme.primary,
            onPressed: picking ? null : onPickCamera,
          ),
          if (picking) ...[
            const SizedBox(width: 4),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
