import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/app_config.dart';
import '../../../domain/entities/message_entity.dart';
import '../../providers/providers.dart';
import '../../widgets/note/message_bubble.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class NoteBoxScreen extends ConsumerStatefulWidget {
  final String placeId;
  final String placeTitle;

  const NoteBoxScreen({
    super.key,
    required this.placeId,
    required this.placeTitle,
  });

  @override
  ConsumerState<NoteBoxScreen> createState() => _NoteBoxScreenState();
}

class _NoteBoxScreenState extends ConsumerState<NoteBoxScreen> {
  final _scrollController = ScrollController();

  // Banner ad — ValueNotifier avoids calling setState() from the ad callback,
  // which previously caused Column layout mutations mid-frame and triggered the
  // '!semantics.parentDataDirty' loop.  Only the ValueListenableBuilder
  // subtree is rebuilt when the ad loads; the rest of the screen is untouched.
  BannerAd? _bannerAd;
  final _adLoaded = ValueNotifier<bool>(false);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAdIfNeeded());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _adLoaded.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  // ── Ad loading ────────────────────────────────────────────────────────────

  void _loadAdIfNeeded() {
    if (ref.read(isPremiumProvider).valueOrNull == true) return;
    _bannerAd = BannerAd(
      adUnitId: AppConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => _adLoaded.value = true,
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  // ── Compose ───────────────────────────────────────────────────────────────

  /// Opens the compose AlertDialog.
  ///
  /// We use `showDialog` (PopupRoute) — proven to coexist safely with this
  /// Scaffold's render tree. Earlier attempts with `Navigator.push` (PageRoute)
  /// and `showModalBottomSheet` with a fixed-height container both triggered
  /// `!semantics.parentDataDirty` / `RenderPhysicalShape was not laid out`,
  /// rooted in computeDryBaseline behaviour around the Material/PhysicalShape
  /// chain (see flutter/flutter#169214, PR #171250).
  ///
  /// `_ComposeResult` carries an optional image attachment along with text.
  Future<void> _openCompose({List<int>? imageBytes, String? imageName}) async {
    final result = await showDialog<_ComposeResult>(
      context: context,
      builder: (_) => _ComposeDialog(
        initialImageBytes: imageBytes,
        initialImageName: imageName,
      ),
    );
    if (result == null || !result.hasContent || !mounted) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    try {
      await ref.read(messageRepositoryProvider).sendMessage(
            placeId: widget.placeId,
            content: result.text,
            userId: user.id,
            userName: user.name,
            userPhotoUrl: user.photoUrl,
            imageBytes: result.imageBytes,
            imageName: result.imageName,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  /// AppBar shortcut: pick a photo via the native UI, then open the compose
  /// dialog with that photo pre-loaded.
  Future<void> _openImagePicker() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _openCompose(imageBytes: bytes, imageName: file.name);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteMessage(MessageEntity message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text(
          'Are you sure you want to delete this message? '
          'It will appear as deleted to all users.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(messageRepositoryProvider)
          .deleteMessage(messageId: message.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  // ── Report ────────────────────────────────────────────────────────────────

  Future<void> _showReportDialog(MessageEntity message) async {
    const reasons = [
      'Spam or advertising',
      'Harassment or bullying',
      'Adult or explicit content',
      'Illegal content',
      'Other',
    ];
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Report message'),
        children: reasons
            .map(
              (r) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, r),
                child: Text(r),
              ),
            )
            .toList(),
      ),
    );
    if (reason == null || !mounted) return;

    final currentUser = ref.read(authStateProvider).valueOrNull;
    if (currentUser == null) return;

    try {
      await ref.read(messageRepositoryProvider).reportMessage(
            messageId: message.id,
            placeId: widget.placeId,
            reporterId: currentUser.id,
            reason: reason,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Report submitted. Thank you for helping keep this community safe.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit report: $e')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.placeId));
    final isPremium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    final currentUser = ref.watch(authStateProvider).valueOrNull;

    // Exclude this screen's semantics while a dialog (delete, report, compose)
    // is shown on top — prevents parentDataDirty noise when two routes coexist.
    final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    // Defensive constraint clamp.  Even with opaque:false on all push routes,
    // any future route that lands on top of NoteBoxScreen with opaque:true
    // would wrap this Scaffold in Offstage(offstage:true), pushing
    // BoxConstraints() (0..∞) into the FAB Column / Scaffold body and
    // re-triggering '!semantics.parentDataDirty' loops.  Same pattern as
    // _MainShell in router.dart.
    final size = MediaQuery.sizeOf(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: size.width,
        maxHeight: size.height,
      ),
      child: ExcludeSemantics(
        excluding: !isCurrent,
        child: Scaffold(
        appBar: AppBar(
          title: Text(widget.placeTitle),
          actions: [
            // Photo shortcut — separate from the compose FAB, opens the
            // native image picker directly, then re-uses the compose dialog
            // with the picked image attached.
            IconButton(
              icon: const Icon(Icons.image_outlined),
              tooltip: 'Add photo',
              onPressed: _openImagePicker,
            ),
            if (!isPremium)
              IconButton(
                icon: const Icon(Icons.star_outline),
                tooltip: 'Go Premium',
                onPressed: () => context.push('/subscription'),
              ),
          ],
        ),
        // Message list — body is the list alone; the FAB and banner are
        // declared separately so the FAB automatically floats above the banner.
        body: messagesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (messages) => messages.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  // Extra bottom padding so the FAB never obscures the last
                  // message (FAB 56 dp + margin 16 dp + breathing room 16 dp).
                  padding: const EdgeInsets.only(top: 8, bottom: 88),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isOwn = message.author.id == currentUser?.id;
                    return MessageBubble(
                      message: message,
                      isOwn: isOwn,
                      onDelete: isOwn
                          ? () => _confirmDeleteMessage(message)
                          : null,
                      onReport: !isOwn
                          ? () => _showReportDialog(message)
                          : null,
                    );
                  },
                ),
        ),

        // Single FAB — proven-stable structure.  Placing widgets in
        // `Scaffold.floatingActionButton` is well exercised by Flutter when
        // it is a single FloatingActionButton; wrapping it in a Column with
        // crossAxisAlignment caused intermittent layout failures alongside
        // the bottomNavigationBar/AnimatedSize combination.  The photo
        // shortcut lives in the AppBar instead.
        // heroTag is unique to prevent Hero conflicts with the map screen's
        // FABs ('mapAddNote', 'tracking').
        floatingActionButton: FloatingActionButton(
          heroTag: 'noteCompose',
          onPressed: () => _openCompose(),
          tooltip: 'Write a message',
          child: const Icon(Icons.edit_outlined),
        ),

        // Banner ad — placed in bottomNavigationBar so the Scaffold
        // automatically lifts the FAB above it when the ad is loaded.
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: _adLoaded,
          builder: (context, loaded, _) {
            final ad = _bannerAd;
            return AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: (loaded && ad != null && !isPremium)
                  ? SafeArea(
                      top: false,
                      child: SizedBox(
                        height: ad.size.height.toDouble(),
                        child: AdWidget(ad: ad),
                      ),
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet.\nBe the first to write!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compose result — what _ComposeDialog returns via Navigator.pop
// ---------------------------------------------------------------------------

class _ComposeResult {
  final String text;
  final List<int>? imageBytes;
  final String? imageName;

  const _ComposeResult({
    required this.text,
    this.imageBytes,
    this.imageName,
  });

  bool get hasContent => text.isNotEmpty || imageBytes != null;
}

// ---------------------------------------------------------------------------
// Compose dialog — AlertDialog (PopupRoute) with TextField + image picker
// ---------------------------------------------------------------------------
//
// AlertDialog is intentionally the *proven-stable* approach for this screen.
// PageRoute-based pushes and showModalBottomSheet with fixed-height containers
// both surfaced layout assertion loops on Flutter 3.44 due to the underlying
// computeDryBaseline / RenderPhysicalShape behaviour. The AlertDialog lets us
// keep the larger TextField (minLines: 8) and inline image attachment without
// triggering those code paths.

class _ComposeDialog extends StatefulWidget {
  final List<int>? initialImageBytes;
  final String? initialImageName;

  const _ComposeDialog({this.initialImageBytes, this.initialImageName});

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();

  List<int>? _imageBytes;
  String? _imageName;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _imageBytes = widget.initialImageBytes;
    _imageName = widget.initialImageName;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
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

  void _submit() {
    final result = _ComposeResult(
      text: _controller.text.trim(),
      imageBytes: _imageBytes,
      imageName: _imageName,
    );
    if (!result.hasContent) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _imageBytes;

    return AlertDialog(
      title: const Text('New message'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Text input — taller minLines for comfortable writing ───
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: null,
              minLines: 8,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Write a message…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── Image attachment row ──────────────────────────────────
            Row(
              children: [
                IconButton.outlined(
                  onPressed: _picking ? null : _pickImage,
                  tooltip: 'Add photo',
                  icon: const Icon(Icons.image_outlined),
                ),
                if (_picking) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                if (bytes != null) ...[
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      Uint8List.fromList(bytes),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _removeImage,
                    tooltip: 'Remove photo',
                    icon: const Icon(Icons.close),
                    iconSize: 18,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Send'),
        ),
      ],
    );
  }
}
