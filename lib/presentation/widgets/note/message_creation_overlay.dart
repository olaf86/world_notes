import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../config/app_config.dart';
import '../../../core/utils/image_upload_util.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/localized_formatters.dart';
import '../../providers/providers.dart';
import 'image_grid_layout.dart';

enum _MessagePublishPreset {
  now('Now', null),
  in15Minutes('15 minutes', Duration(minutes: 15)),
  in30Minutes('30 minutes', Duration(minutes: 30)),
  in1Hour('1 hour', Duration(hours: 1)),
  in3Hours('3 hours', Duration(hours: 3)),
  custom('Custom', null);

  final String label;
  final Duration? delay;

  const _MessagePublishPreset(this.label, this.delay);
}

/// Full-screen "new message" editor rendered as an **overlay inside
/// NoteBoxScreen**, not as a separate Navigator route.
///
/// Why an overlay rather than a Route push?
///
/// Every attempt to present the message editor through a Navigator route —
/// whether
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

  // Stored as Uint8List (not List<int>) so that the same instances are reused
  // across rebuilds. MemoryImage uses reference equality on the byte array;
  // recreating them every build can cause a white-flash flicker.
  final List<Uint8List> _imageBytesList = [];
  String? _pendingMessageId;
  _MessagePublishPreset _publishPreset = _MessagePublishPreset.now;
  DateTime? _customPublishAt;
  bool _showScheduleOptions = false;
  bool _isSending = false;
  bool _picking = false;

  static const _pickerImageQuality = 100;
  static final double _pickerMaxDimension = ImageUploadUtil.maxDimension
      .toDouble();

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
      _controller.text.trim().isNotEmpty || _imageBytesList.isNotEmpty;

  // ── Image picking ─────────────────────────────────────────────────────────

  Future<List<XFile>> _pickGalleryFiles(int limit) {
    return _picker.pickMultiImage(
      imageQuality: _pickerImageQuality,
      maxWidth: _pickerMaxDimension,
      maxHeight: _pickerMaxDimension,
      limit: limit,
    );
  }

  Future<XFile?> _pickCameraFile() {
    return _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: _pickerImageQuality,
      maxWidth: _pickerMaxDimension,
      maxHeight: _pickerMaxDimension,
    );
  }

  Future<List<Uint8List>> _compressPickedFiles(Iterable<XFile> files) {
    return Future.wait(
      files.map((file) async {
        return ImageUploadUtil.compressToWebP(await file.readAsBytes());
      }),
    );
  }

  Future<void> _pickGalleryImages() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final remaining = AppConfig.maxMessageImages - _imageBytesList.length;
      if (remaining <= 0) return;
      final files = await _pickGalleryFiles(remaining);
      if (files.isEmpty || !mounted) return;

      final compressed = await _compressPickedFiles(files.take(remaining));
      if (!mounted) return;

      setState(() {
        _imageBytesList.addAll(compressed);
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          duration: const Duration(seconds: 4),
        ),
      );
    } on UnsupportedError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WebP encoding is not supported on this device.'),
          duration: Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickCameraImage() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      if (_imageBytesList.length >= AppConfig.maxMessageImages) return;
      final file = await _pickCameraFile();
      if (file == null || !mounted) return;
      final bytes = (await _compressPickedFiles([file])).single;
      if (!mounted) return;

      setState(() {
        _imageBytesList.add(bytes);
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          duration: const Duration(seconds: 4),
        ),
      );
    } on UnsupportedError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WebP encoding is not supported on this device.'),
          duration: Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removeImageAt(int index) => setState(() {
    _imageBytesList.removeAt(index);
  });

  static const _maxChars = 2000;

  DateTime _defaultCustomPublishAt() {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(hours: 1));
  }

  DateTime? _publishAtForSend() {
    if (_publishPreset == _MessagePublishPreset.now) return null;
    if (_publishPreset == _MessagePublishPreset.custom) {
      return _customPublishAt ?? _defaultCustomPublishAt();
    }
    final delay = _publishPreset.delay;
    return delay == null ? null : DateTime.now().add(delay);
  }

  bool get _isScheduled => _publishPreset != _MessagePublishPreset.now;

  String _publishLabel() {
    if (_publishPreset == _MessagePublishPreset.now) return 'Now';
    if (_publishPreset != _MessagePublishPreset.custom) {
      return _publishPreset.label;
    }
    final value = _customPublishAt ?? _defaultCustomPublishAt();
    return formatMessageDateTime(
      value,
      locale: context.localeTag,
      includeDate: true,
    );
  }

  Future<void> _pickCustomPublishTime() async {
    final initial = _customPublishAt ?? _defaultCustomPublishAt();
    final now = DateTime.now();
    final latest = now.add(
      const Duration(days: AppConfig.maxMessagePublishDelayDays),
    );
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: latest,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    var selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (selected.isBefore(now)) {
      selected = now.add(const Duration(minutes: 1));
    }
    if (selected.isAfter(latest)) {
      selected = latest;
    }
    setState(() {
      _publishPreset = _MessagePublishPreset.custom;
      _customPublishAt = selected;
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_hasContent || _isSending) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    final messageId = _pendingMessageId ?? const Uuid().v7();
    _pendingMessageId = messageId;
    setState(() => _isSending = true);
    try {
      await ref
          .read(messageRepositoryProvider)
          .sendMessage(
            id: messageId,
            placeId: widget.placeId,
            content: _controller.text.trim(),
            userId: user.id,
            userName: user.name,
            userPhotoUrl: user.photoUrl,
            imageBytesList: _imageBytesList,
            publishAt: _publishAtForSend(),
          );
      _pendingMessageId = null;
      if (mounted) widget.onClose();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      final message = _imageBytesList.isNotEmpty
          ? 'Failed to upload image. '
                'Check that Firebase Storage is enabled and security rules allow writes.\n$e'
          : 'Failed to send: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    final canAddImages = _imageBytesList.length < AppConfig.maxMessageImages;

    return Material(
      color: theme.colorScheme.surface,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardBottom),
        child: SafeArea(
          bottom: keyboardBottom == 0,
          child: Column(
            children: [
              _Header(
                isSending: _isSending,
                canSend: _hasContent,
                onClose: widget.onClose,
                onSend: _submit,
                charCount: _controller.text.length,
                maxChars: _maxChars,
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
                    maxLength: _maxChars,
                    // Hide the default counter — we show it in the header instead.
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_maxChars),
                    ],
                    decoration: const InputDecoration(
                      hintText: "What's happening at this place?",
                      // Remove Material 3's default filled look (grey tinted
                      // background + rounded corners).  The editor lives
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
              if (_imageBytesList.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _ImagePreviewGrid(
                    images: _imageBytesList,
                    onRemove: _removeImageAt,
                  ),
                ),

              const Divider(height: 1),

              if (_showScheduleOptions)
                _ScheduleOptions(
                  selected: _publishPreset,
                  label: _publishLabel(),
                  isSending: _isSending,
                  onSelected: (preset) {
                    setState(() {
                      _publishPreset = preset;
                      if (preset == _MessagePublishPreset.custom) {
                        _customPublishAt ??= _defaultCustomPublishAt();
                      }
                    });
                  },
                  onPickCustom: _pickCustomPublishTime,
                ),

              // Keyboard-aware attachment toolbar.
              _AttachmentToolbar(
                picking: _picking,
                canAddImages: canAddImages,
                scheduleLabel: _publishLabel(),
                scheduled: _isScheduled,
                onPickGallery: _pickGalleryImages,
                onPickCamera: _pickCameraImage,
                onToggleSchedule: () {
                  setState(() => _showScheduleOptions = !_showScheduleOptions);
                },
              ),
            ],
          ),
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
  final int charCount;
  final int maxChars;

  const _Header({
    required this.isSending,
    required this.canSend,
    required this.onClose,
    required this.onSend,
    required this.charCount,
    required this.maxChars,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = maxChars - charCount;
    // Turn red when fewer than 100 characters remain.
    final counterColor = remaining < 100
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

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
            child: Text('New message', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '$charCount/$maxChars',
              style: theme.textTheme.bodySmall?.copyWith(
                color: counterColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
// Image preview grid with remove buttons
// ---------------------------------------------------------------------------

class _ImagePreviewGrid extends StatelessWidget {
  final List<Uint8List> images;
  final ValueChanged<int> onRemove;

  const _ImagePreviewGrid({required this.images, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 180,
        child: ImageGridLayout(
          itemCount: images.length,
          itemBuilder: (context, index) => _RemovableImagePreview(
            bytes: images[index],
            onRemove: () => onRemove(index),
          ),
        ),
      ),
    );
  }
}

class _RemovableImagePreview extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onRemove;

  const _RemovableImagePreview({required this.bytes, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(bytes, fit: BoxFit.cover),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close, size: 18, color: Colors.white),
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
  final bool canAddImages;
  final String scheduleLabel;
  final bool scheduled;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onToggleSchedule;

  const _AttachmentToolbar({
    required this.picking,
    required this.canAddImages,
    required this.scheduleLabel,
    required this.scheduled,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onToggleSchedule,
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
            onPressed: picking || !canAddImages ? null : onPickGallery,
          ),
          IconButton(
            tooltip: 'Take a photo',
            icon: const Icon(Icons.camera_alt_outlined),
            color: theme.colorScheme.primary,
            onPressed: picking || !canAddImages ? null : onPickCamera,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onToggleSchedule,
            icon: Icon(
              scheduled ? Icons.schedule_send_outlined : Icons.schedule,
              size: 18,
            ),
            label: Text(scheduleLabel),
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

class _ScheduleOptions extends StatelessWidget {
  final _MessagePublishPreset selected;
  final String label;
  final bool isSending;
  final ValueChanged<_MessagePublishPreset> onSelected;
  final VoidCallback onPickCustom;

  const _ScheduleOptions({
    required this.selected,
    required this.label,
    required this.isSending,
    required this.onSelected,
    required this.onPickCustom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.schedule_send_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Post time', style: theme.textTheme.titleSmall),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _MessagePublishPreset.values.map((preset) {
                return ChoiceChip(
                  label: Text(preset.label),
                  selected: selected == preset,
                  onSelected: isSending
                      ? null
                      : (_) {
                          onSelected(preset);
                          if (preset == _MessagePublishPreset.custom) {
                            onPickCustom();
                          }
                        },
                );
              }).toList(),
            ),
            if (selected == _MessagePublishPreset.custom) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: isSending ? null : onPickCustom,
                icon: const Icon(Icons.event_outlined),
                label: Text(label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
