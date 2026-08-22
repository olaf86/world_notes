import 'package:flutter/foundation.dart';

import '../../../domain/entities/pin_summary_entity.dart';
import 'apple_note_map_controller.dart';
import 'google_note_map_controller.dart';
import 'note_map_adapter.dart';

NoteMapAdapter createNoteMapAdapter({
  required Future<void> Function(PinSummary pin) onPinSelected,
  required OnResolvePinMarkerImage onResolveMarkerImage,
}) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return AppleNoteMapController(
      onPinSelected: onPinSelected,
      onResolveMarkerImage: onResolveMarkerImage,
    );
  }

  return GoogleNoteMapController(
    onPinSelected: onPinSelected,
    onResolveMarkerImage: onResolveMarkerImage,
  );
}
