import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/providers.dart';

/// Full-screen "new message" composition view.
///
/// Pushed from [NoteBoxScreen] as `/note/:placeId/post` inside the note
/// `ShellRoute` (see router.dart).  Because the push happens within the
/// note shell's Navigator — not the root Navigator — the offstage chain
/// that previously triggered `!semantics.parentDataDirty` is contained to
/// a much smaller render tree.  Combined with `opaque: false` on this
/// route, NoteBoxScreen stays laid out beneath without complication.
class MessageCreationScreen extends ConsumerStatefulWidget {
  final String placeId;

  const MessageCreationScreen({super.key, required this.placeId});

  @override
  ConsumerState<MessageCreationScreen> createState() =>
      _MessageCreationScreenState();
}

class _MessageCreationScreenState
    extends ConsumerState<MessageCreationScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();

  List<int>? _imageBytes;
  String? _imageName;
  bool _isSending = false;
  bool _picking = false;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    // Defer focus / keyboard until the slide-up animation completes so the
    // keyboard's viewInsets change doesn't race with the route's first
    // layout pass.
    WidgetsBinding.instance.addPostFrameCallback(_requestFocusWhenReady);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _requestFocusWhenReady(Duration _) {
    if (!mounted) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _focusNode.requestFocus();
      return;
    }
    _routeAnimation = animation;
    animation.addStatusListener(_onRouteAnimationStatus);
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
      _routeAnimation = null;
      if (mounted) _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Send is enabled only when there is text or an image attachment.
  bool get _hasContent =>
      _controller.text.trim().isNotEmpty || _imageBytes != null;

  // ── Image picking ─────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
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
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _imageBytes;

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('New message'),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
            child: _isSending
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton(
                    // Disabled while there is no text and no image — the X /
                    // Twitter pattern.
                    onPressed: _hasContent ? _submit : null,
                    child: const Text('Send'),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Text editor — fills all available vertical space ──────────────
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
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),

          // ── Image attachment preview ──────────────────────────────────────
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
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
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

          const Divider(height: 1),

          // ── Attachment toolbar — Twitter-style icon row above the keyboard
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Choose from library',
                    icon: const Icon(Icons.image_outlined),
                    color: theme.colorScheme.primary,
                    onPressed: _picking
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                  ),
                  IconButton(
                    tooltip: 'Take a photo',
                    icon: const Icon(Icons.camera_alt_outlined),
                    color: theme.colorScheme.primary,
                    onPressed: _picking
                        ? null
                        : () => _pickImage(ImageSource.camera),
                  ),
                  if (_picking) ...[
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
            ),
          ),
        ],
      ),
    );
  }
}
