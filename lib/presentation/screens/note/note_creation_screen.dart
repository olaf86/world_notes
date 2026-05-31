import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../providers/providers.dart';

class NoteCreationScreen extends ConsumerStatefulWidget {
  final double latitude;
  final double longitude;

  const NoteCreationScreen({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  ConsumerState<NoteCreationScreen> createState() => _NoteCreationScreenState();
}

class _NoteCreationScreenState extends ConsumerState<NoteCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();

  Color _selectedColor = Colors.green;
  String _selectedIcon = 'place';
  // Expiry is required. Default to 90 days (3 months) — a balanced lifetime
  // that keeps the map from filling with stale notes while not feeling
  // aggressively short.
  int _expiryDays = 90;
  bool _loading = false;

  /// Human-readable label for an expiry preset (in days).
  static String _expiryLabel(int days) => switch (days) {
        7 => '1 week',
        30 => '1 month',
        90 => '3 months',
        180 => '6 months',
        365 => '1 year',
        _ => '$days days',
      };

  static const _colors = [
    Colors.green,
    Colors.blue,
    Colors.red,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.brown,
  ];

  static const _icons = [
    ('place', Icons.place),
    ('restaurant', Icons.restaurant),
    ('park', Icons.park),
    ('home', Icons.home),
    ('star', Icons.star),
    ('photo', Icons.photo_camera),
    ('music', Icons.music_note),
  ];

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

      // Flutter 3.27+: Color.r/g/b return double (0.0–1.0), multiply by 255.
      final r = (_selectedColor.r * 255).round().toRadixString(16).padLeft(2, '0');
      final g = (_selectedColor.g * 255).round().toRadixString(16).padLeft(2, '0');
      final b = (_selectedColor.b * 255).round().toRadixString(16).padLeft(2, '0');
      final colorHex = '#$r$g$b'.toUpperCase();

      final place = await ref.read(placeRepositoryProvider).createPlace(
            latitude: widget.latitude,
            longitude: widget.longitude,
            title: _titleController.text.trim(),
            subtitle: _subtitleController.text.trim().isEmpty
                ? null
                : _subtitleController.text.trim(),
            colorHex: colorHex,
            icon: _selectedIcon,
            createdByUserId: user.id,
            expiresAt: DateTime.now().add(Duration(days: _expiryDays)),
          );

      if (mounted) {
        context.pushReplacement(
          '/note/${place.id}?title=${Uri.encodeComponent(place.title)}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Note')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            const SizedBox(height: 24),
            Text(
              'Color',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: _colors.map((color) {
                final isSelected = _selectedColor == color;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text(
              'Icon',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: _icons.map((item) {
                final (key, iconData) = item;
                final isSelected = _selectedIcon == key;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIcon = key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _selectedColor
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      iconData,
                      color: isSelected
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text(
              'Auto-close after',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'The note stops accepting messages and is archived when this '
              'period ends.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: AppConfig.noteExpiryPresetDays.map((days) {
                return ChoiceChip(
                  label: Text(_expiryLabel(days)),
                  selected: _expiryDays == days,
                  onSelected: (_) => setState(() => _expiryDays = days),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _loading ? null : _create,
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
