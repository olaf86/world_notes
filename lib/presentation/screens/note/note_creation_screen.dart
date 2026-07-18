import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../config/app_config.dart';
import '../../../core/utils/place_icon.dart';
import '../../../domain/entities/place_entity.dart';
import '../../../domain/entities/note_theme.dart';
import '../../../services/location_service.dart';
import '../../providers/providers.dart';
import '../../widgets/note/fork_location_notice.dart';
import '../../widgets/note/note_lock_setup_dialog.dart';
import '../../widgets/note/note_lock_summary.dart';
import '../../widgets/note/note_theme_picker.dart';
import '../../widgets/note/pin_color_picker.dart';
import '../../widgets/note/pin_icon_picker.dart';
import '../../widgets/note/pin_image_summary.dart';
import '../../widgets/note/pin_thumbnail_crop_dialog.dart';

enum _PublicationPreset {
  now('Now', null),
  in15Minutes('15 minutes', Duration(minutes: 15)),
  in30Minutes('30 minutes', Duration(minutes: 30)),
  in1Hour('1 hour', Duration(hours: 1)),
  in3Hours('3 hours', Duration(hours: 3)),
  tomorrow('Tomorrow', Duration(hours: 24)),
  custom('Custom', null);

  final String label;
  final Duration? delay;

  const _PublicationPreset(this.label, this.delay);
}

enum _PinMarkerStyle { icon, image }

/// Values copied from an archived note when creating a new note from it.
class NoteCreationDraft {
  final double latitude;
  final double longitude;
  final String title;
  final String? subtitle;
  final String colorHex;
  final String icon;
  final NoteThemeId themeId;

  const NoteCreationDraft({
    required this.latitude,
    required this.longitude,
    required this.title,
    this.subtitle,
    required this.colorHex,
    required this.icon,
    this.themeId = NoteThemeId.standard,
  });

  factory NoteCreationDraft.fromPlace(PlaceEntity place) => NoteCreationDraft(
    latitude: place.latitude,
    longitude: place.longitude,
    title: place.title,
    subtitle: place.subtitle,
    colorHex: place.colorHex,
    icon: place.icon,
    themeId: place.themeId,
  );
}

class NoteCreationScreen extends ConsumerStatefulWidget {
  final NoteCreationDraft? forkDraft;

  const NoteCreationScreen({super.key, this.forkDraft});

  @override
  ConsumerState<NoteCreationScreen> createState() => _NoteCreationScreenState();
}

class _NoteCreationScreenState extends ConsumerState<NoteCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _imagePicker = ImagePicker();

  Color _selectedColor = Colors.green;
  String _selectedIcon = defaultMapPinIcon;
  NoteThemeId _selectedTheme = NoteThemeId.standard;
  _PinMarkerStyle _pinMarkerStyle = _PinMarkerStyle.icon;
  Uint8List? _pinThumbnailBytes;
  // Expiry is required. Defaults to AppConfig.defaultNoteExpiryDays (3 months)
  // — a balanced lifetime that keeps the map from filling with stale notes
  // while not feeling aggressively short.
  int _expiryDays = AppConfig.defaultNoteExpiryDays;
  _PublicationPreset _publicationPreset = _PublicationPreset.now;
  DateTime? _customPublishAt;
  NoteLockSetupValue? _lockSetup;
  bool _loading = false;
  bool _pickingPinImage = false;
  bool _showMoreColors = false;
  bool _showMoreIcons = false;

  /// Human-readable label for an expiry preset (in days).
  static String _expiryLabel(int days) => switch (days) {
    7 => '1 week',
    30 => '1 month',
    90 => '3 months',
    180 => '6 months',
    365 => '1 year',
    _ => '$days days',
  };

  static const List<Color> _colors = [
    Colors.green,
    Colors.blue,
    Colors.red,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.brown,
    Colors.indigo,
    Colors.cyan,
    Colors.lime,
    Colors.amber,
    Colors.deepOrange,
    Colors.blueGrey,
  ];

  static const _icons = [
    PinIconOption('place', Icons.place),
    PinIconOption('restaurant', Icons.restaurant),
    PinIconOption('park', Icons.park),
    PinIconOption('home', Icons.home),
    PinIconOption('star', Icons.star),
    PinIconOption('photo', Icons.photo_camera),
    PinIconOption('music', Icons.music_note),
    PinIconOption('coffee', Icons.coffee),
    PinIconOption('shopping', Icons.shopping_bag),
    PinIconOption('hotel', Icons.hotel),
    PinIconOption('directions', Icons.directions_car),
    PinIconOption('hiking', Icons.hiking),
    PinIconOption('pets', Icons.pets),
    PinIconOption('work', Icons.work),
    PinIconOption('favorite', Icons.favorite),
  ];

  static const int _inlineOptionCount = 5;

  @override
  void initState() {
    super.initState();
    final draft = widget.forkDraft;
    if (draft == null) return;

    _titleController.text = draft.title;
    _subtitleController.text = draft.subtitle ?? '';
    _selectedColor = parsePlaceColor(draft.colorHex);
    _selectedTheme = draft.themeId;
    if (_icons.any((item) => item.id == draft.icon)) {
      _selectedIcon = draft.icon;
    }
  }

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

  DateTime? _publishAtForCreate() {
    if (_publicationPreset == _PublicationPreset.now) return null;
    if (_publicationPreset == _PublicationPreset.custom) {
      return _customPublishAt ?? _defaultCustomPublishAt();
    }
    final delay = _publicationPreset.delay;
    return delay == null ? null : DateTime.now().add(delay);
  }

  String _publicationLabel(DateTime value) {
    return DateFormat('MMM d, yyyy HH:mm').format(value.toLocal());
  }

  Future<void> _pickPublicationTime() async {
    final initial = _customPublishAt ?? _defaultCustomPublishAt();
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: AppConfig.maxNoteLifetimeDays)),
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
    setState(() {
      _publicationPreset = _PublicationPreset.custom;
      _customPublishAt = selected;
    });
  }

  void _showPatternTooLongSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pattern is too long. Use 30 nodes or fewer.'),
      ),
    );
  }

  Future<void> _configureLock() async {
    final value = await showDialog<NoteLockSetupValue>(
      context: context,
      builder: (_) => NoteLockSetupDialog(
        title: _lockSetup == null ? 'Set lock' : 'Change lock',
        submitLabel: _lockSetup == null ? 'Use lock' : 'Update',
        initialLockType: _lockSetup?.lockType,
        initialHint: _lockSetup?.lockHint,
        onPatternTooLong: _showPatternTooLongSnack,
      ),
    );
    if (value == null || !mounted) return;
    setState(() => _lockSetup = value);
  }

  void _removeLock() {
    setState(() => _lockSetup = null);
  }

  Future<void> _pickPinImage() async {
    if (_pickingPinImage) return;
    setState(() => _pickingPinImage = true);
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (file == null || !mounted) return;
      final sourceBytes = await file.readAsBytes();
      if (!mounted) return;

      final thumbnail = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PinThumbnailCropDialog(imageBytes: sourceBytes),
      );
      if (thumbnail == null || !mounted) return;

      setState(() => _pinThumbnailBytes = thumbnail);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not prepare the pin image: $error'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingPinImage = false);
    }
  }

  void _removePinImage() {
    setState(() => _pinThumbnailBytes = null);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showLocationSetupDialog({
    required String title,
    required String message,
    required String actionLabel,
    required Future<bool> Function() openSettings,
  }) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.settings_outlined),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
    if (shouldOpen == true) await openSettings();
  }

  Future<void> _handleLocationAvailabilityIssue(
    LocationAvailabilityIssue issue,
  ) async {
    switch (issue) {
      case LocationAvailabilityIssue.permissionPermanentlyDenied:
        await _showLocationSetupDialog(
          title: 'Location permission needed',
          message:
              'Location permission is disabled. Open system settings and '
              'allow location access to create notes.',
          actionLabel: 'Open settings',
          openSettings: Geolocator.openAppSettings,
        );
      case LocationAvailabilityIssue.permissionDenied:
        _showSnack('Location permission is required to create a note.');
      case LocationAvailabilityIssue.serviceDisabled:
        await _showLocationSetupDialog(
          title: 'Turn on location services',
          message:
              'Location services are turned off. Turn them on to create a note '
              'at your current location.',
          actionLabel: 'Open settings',
          openSettings: Geolocator.openLocationSettings,
        );
    }
  }

  Future<Position?> _currentPositionForCreate() async {
    try {
      return await ref.read(locationServiceProvider).getCurrentPosition();
    } catch (error) {
      if (!mounted) return null;
      final issue = locationAvailabilityIssueFromError(error);
      if (issue != null) {
        await _handleLocationAvailabilityIssue(issue);
        return null;
      }
      _showSnack('Could not get your current location. Please try again.');
      return null;
    }
  }

  Future<({double latitude, double longitude})?> _coordinatesForCreate() async {
    final draft = widget.forkDraft;
    if (draft != null) {
      return (latitude: draft.latitude, longitude: draft.longitude);
    }

    final position = await _currentPositionForCreate();
    if (position == null) return null;
    return (latitude: position.latitude, longitude: position.longitude);
  }

  Future<void> _reportPinImageUploadError({
    required String placeId,
    required Object error,
    required StackTrace stack,
  }) async {
    try {
      final crashlytics = ref.read(firebaseCrashlyticsProvider);
      await crashlytics.log('Note pin image upload failed for place $placeId');
      await crashlytics.setCustomKey('note_pin_image_place_id', placeId);
      await crashlytics.recordError(
        error,
        stack,
        reason: 'Note pin image upload failed after note creation',
        fatal: false,
      );
    } catch (crashlyticsError, crashlyticsStack) {
      debugPrint(
        '[NoteCreation] Could not report pin image upload failure: '
        '$crashlyticsError\n$crashlyticsStack',
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null) throw Exception('Not signed in');
      final coordinates = await _coordinatesForCreate();
      if (coordinates == null) return;

      // Flutter 3.27+: Color.r/g/b return double (0.0–1.0), multiply by 255.
      final r = (_selectedColor.r * 255)
          .round()
          .toRadixString(16)
          .padLeft(2, '0');
      final g = (_selectedColor.g * 255)
          .round()
          .toRadixString(16)
          .padLeft(2, '0');
      final b = (_selectedColor.b * 255)
          .round()
          .toRadixString(16)
          .padLeft(2, '0');
      final colorHex = '#$r$g$b'.toUpperCase();

      final title = _titleController.text.trim();
      final lockSetup = _lockSetup;
      final icon = _pinMarkerStyle == _PinMarkerStyle.image
          ? defaultMapPinIcon
          : _selectedIcon;
      final pinThumbnailBytes = _pinMarkerStyle == _PinMarkerStyle.image
          ? _pinThumbnailBytes
          : null;
      final placeId = await ref
          .read(placeRepositoryProvider)
          .createNote(
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            title: title,
            subtitle: _subtitleController.text.trim().isEmpty
                ? null
                : _subtitleController.text.trim(),
            colorHex: colorHex,
            themeId: _selectedTheme,
            icon: icon,
            expiryDays: _expiryDays,
            publishAt: _publishAtForCreate(),
            visibility: lockSetup == null
                ? PlaceVisibility.public
                : PlaceVisibility.private,
            lock: lockSetup == null
                ? null
                : NoteLockDraft(
                    lockType: lockSetup.lockType,
                    secret: lockSetup.secret,
                    lockHint: lockSetup.lockHint,
                  ),
          );
      if (pinThumbnailBytes != null) {
        try {
          await ref
              .read(placeRepositoryProvider)
              .setNotePinImage(
                placeId: placeId,
                userId: user.id,
                thumbnailBytes: pinThumbnailBytes,
              );
        } catch (error, stack) {
          await _reportPinImageUploadError(
            placeId: placeId,
            error: error,
            stack: stack,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Note created, but pin image upload failed: $error',
                ),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
      ref.invalidate(mapPinsProvider);
      ref.invalidate(myPlacesProvider);

      if (mounted) {
        context.pushReplacement(
          '/note/$placeId?title=${Uri.encodeComponent(title)}',
        );
      }
    } on FirebaseFunctionsException catch (e) {
      // createNote runs server-side, so failures arrive as callable errors.
      // Method A: note creation requires connectivity — tell the user plainly
      // when the network is the problem instead of a generic error.
      final message = switch (e.code) {
        'unavailable' || 'deadline-exceeded' =>
          'Couldn\'t reach the server. Check your internet connection and try again.',
        'resource-exhausted' => e.message ?? 'You\'ve reached your note limit.',
        'unauthenticated' => 'Please sign in again to create a note.',
        _ => e.message ?? 'Could not create the note. Please try again.',
      };
      if (mounted) {
        _showSnack(message);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forkDraft = widget.forkDraft;
    final activeCount = ref.watch(activeMyPlacesCountProvider);
    final noteLimit = ref.watch(noteLimitProvider);
    final isPremium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    final limitReached = switch (activeCount.valueOrNull) {
      final count? => count >= noteLimit,
      null => false,
    };
    final canSubmit = !_loading && !activeCount.isLoading && !limitReached;
    return Scaffold(
      appBar: AppBar(title: const Text('New Note')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _NoteCapacityStatus(
              activeCount: activeCount,
              limit: noteLimit,
              isPremium: isPremium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'What is this place?',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _subtitleController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Tell us about this place...',
              ),
              maxLines: 3,
            ),
            if (forkDraft != null) ...[
              const SizedBox(height: 16),
              const ForkLocationNotice(),
            ],
            const SizedBox(height: 24),
            Text('Note theme', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            NoteThemePicker(
              selected: _selectedTheme,
              onChanged: (theme) => setState(() => _selectedTheme = theme),
            ),
            const SizedBox(height: 16),
            Text('Pin color', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            PinColorPicker(
              colors: _colors,
              selected: _selectedColor,
              showMore: _showMoreColors,
              inlineOptionCount: _inlineOptionCount,
              onSelected: (color) => setState(() => _selectedColor = color),
              onToggleMore: () {
                setState(() => _showMoreColors = !_showMoreColors);
              },
            ),
            const SizedBox(height: 24),
            Text('Pin style', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<_PinMarkerStyle>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _PinMarkerStyle.image,
                  icon: Icon(Icons.image_outlined),
                  label: Text('Pin image'),
                ),
                ButtonSegment(
                  value: _PinMarkerStyle.icon,
                  icon: Icon(Icons.place_outlined),
                  label: Text('Icon'),
                ),
              ],
              selected: {_pinMarkerStyle},
              onSelectionChanged: (selection) {
                setState(() => _pinMarkerStyle = selection.single);
              },
            ),
            const SizedBox(height: 16),
            if (_pinMarkerStyle == _PinMarkerStyle.icon) ...[
              Text('Icon', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              PinIconPicker(
                icons: _icons,
                selected: _selectedIcon,
                selectedColor: _selectedColor,
                showMore: _showMoreIcons,
                inlineOptionCount: _inlineOptionCount,
                onSelected: (icon) => setState(() => _selectedIcon = icon),
                onToggleMore: () {
                  setState(() => _showMoreIcons = !_showMoreIcons);
                },
              ),
            ] else ...[
              Text('Image', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              PinImageSummary(
                bytes: _pinThumbnailBytes,
                selectedColor: _selectedColor,
                selectedIcon: defaultMapPinIcon,
                picking: _pickingPinImage,
                onPick: _pickPinImage,
                onRemove: _removePinImage,
              ),
            ],
            const SizedBox(height: 24),
            Text('Publish', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Now')),
                ButtonSegment(value: true, label: Text('Later')),
              ],
              selected: {_publicationPreset != _PublicationPreset.now},
              onSelectionChanged: (selection) {
                final isLater = selection.single;
                setState(() {
                  _publicationPreset = isLater
                      ? (_publicationPreset == _PublicationPreset.now
                            ? _PublicationPreset.in15Minutes
                            : _publicationPreset)
                      : _PublicationPreset.now;
                });
              },
            ),
            if (_publicationPreset != _PublicationPreset.now) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<_PublicationPreset>(
                initialValue: _publicationPreset,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Publish later',
                  border: OutlineInputBorder(),
                ),
                items: _PublicationPreset.values
                    .where((preset) => preset != _PublicationPreset.now)
                    .map(
                      (preset) => DropdownMenuItem(
                        value: preset,
                        child: Text(preset.label),
                      ),
                    )
                    .toList(),
                onChanged: (preset) {
                  if (preset == null) return;
                  if (preset == _PublicationPreset.custom) {
                    _pickPublicationTime();
                    return;
                  }
                  setState(() => _publicationPreset = preset);
                },
              ),
              if (_publicationPreset == _PublicationPreset.custom) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickPublicationTime,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _publicationLabel(
                      _customPublishAt ?? _defaultCustomPublishAt(),
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Auto-close after',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Tooltip(
                  message:
                      'Stops accepting messages and archives the note after this period.',
                  child: Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _expiryDays,
                  underline: const SizedBox.shrink(),
                  items: AppConfig.noteExpiryPresetDays
                      .map(
                        (days) => DropdownMenuItem(
                          value: days,
                          child: Text(_expiryLabel(days)),
                        ),
                      )
                      .toList(),
                  onChanged: (days) {
                    if (days != null) setState(() => _expiryDays = days);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Access', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            NoteLockSummary(
              value: _lockSetup,
              onConfigure: _configureLock,
              onRemove: _removeLock,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: canSubmit ? _create : null,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Note'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCapacityStatus extends StatelessWidget {
  final AsyncValue<int?> activeCount;
  final int limit;
  final bool isPremium;

  const _NoteCapacityStatus({
    required this.activeCount,
    required this.limit,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    if (activeCount.isLoading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(),
          SizedBox(height: 8),
          Text('Checking available note slots...'),
        ],
      );
    }

    final count = activeCount.valueOrNull;
    if (count == null || count < limit) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Note limit reached',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isPremium
                  ? 'You have $count of $limit active notes. Archive one or '
                        'wait for one to expire before creating another.'
                  : 'Free accounts can keep $limit active notes. Archive one '
                        'or upgrade to PRO for up to '
                        '${AppConfig.proNoteLimit}.',
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
            if (!isPremium) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/subscription'),
                child: const Text('Go PRO'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
