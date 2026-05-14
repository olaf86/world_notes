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

class NoteBoxScreen extends ConsumerStatefulWidget {
  final String noteId;
  final String placeTitle;

  const NoteBoxScreen({super.key, required this.noteId, required this.placeTitle});

  @override
  ConsumerState<NoteBoxScreen> createState() => _NoteBoxScreenState();
}

class _NoteBoxScreenState extends ConsumerState<NoteBoxScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  BannerAd? _bannerAd;
  bool _adLoaded = false;
  Uint8List? _pendingImageBytes;
  String? _pendingImageName;

  // Older messages loaded via pagination (appended below the stream window).
  final List<MessageEntity> _olderMessages = [];
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadAd();
    _scrollController.addListener(_onScroll);
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: AppConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _adLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  void _onScroll() {
    // ListView is reverse:true — maxScrollExtent is the "top" (oldest messages).
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;

    // Determine the oldest message currently shown.
    final streamMessages =
        ref.read(messagesProvider(widget.noteId)).valueOrNull ?? [];
    final allVisible = [...streamMessages, ..._olderMessages];
    if (allVisible.isEmpty) return;

    setState(() => _loadingMore = true);

    try {
      final fetched = await ref
          .read(messageRepositoryProvider)
          .getOlderMessages(
            noteId: widget.noteId,
            beforeMessageId: allVisible.last.id,
            limit: AppConfig.messagesPageSize,
          );
      setState(() {
        _olderMessages.addAll(fetched);
        _hasMore = fetched.length == AppConfig.messagesPageSize;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final isPremium = ref.read(isPremiumProvider).valueOrNull ?? false;
    if (!isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo attachments require Premium.')),
      );
      return;
    }
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pendingImageBytes = bytes;
      _pendingImageName = file.name;
    });
  }

  void _clearPendingImage() {
    setState(() {
      _pendingImageBytes = null;
      _pendingImageName = null;
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _pendingImageBytes == null) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    final imageBytes = _pendingImageBytes;
    final imageName = _pendingImageName;
    _messageController.clear();
    _clearPendingImage();

    try {
      await ref.read(messageRepositoryProvider).sendMessage(
            noteId: widget.noteId,
            content: text,
            userId: user.id,
            imageBytes: imageBytes,
            imageName: imageName,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.noteId));
    final isPremiumAsync = ref.watch(isPremiumProvider);
    final isPremium = isPremiumAsync.valueOrNull ?? false;
    final currentUser = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.placeTitle),
        actions: [
          if (!isPremium)
            IconButton(
              icon: const Icon(Icons.star_outline),
              tooltip: 'Go Premium',
              onPressed: () => context.push('/subscription'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Banner ad (non-premium only)
          if (!isPremium && _adLoaded && _bannerAd != null)
            SizedBox(
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),

          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (streamMessages) {
                final allMessages = [...streamMessages, ..._olderMessages];

                if (allMessages.isEmpty) {
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  // Extra item at the end for the loading indicator.
                  itemCount: allMessages.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == allMessages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final message = allMessages[index];
                    final isOwn = message.author.id == currentUser?.id;
                    return MessageBubble(message: message, isOwn: isOwn);
                  },
                );
              },
            ),
          ),

          // Message input
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              8,
              8 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pendingImageBytes != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _pendingImageBytes!,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        GestureDetector(
                          onTap: _clearPendingImage,
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_outlined),
                      tooltip: 'Attach photo (Premium)',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Write a message...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
