import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/place_entity.dart';
import 'apple_note_map_controller.dart';
import 'maplibre_note_map_adapter.dart';
import 'note_map_adapter.dart';

NoteMapAdapter createNoteMapAdapter({
  required TickerProvider vsync,
  required Future<void> Function(PlaceEntity place) onPinSelected,
}) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return AppleNoteMapController(onPinSelected: onPinSelected);
  }

  return MapLibreNoteMapAdapter(vsync: vsync, onPinSelected: onPinSelected);
}
