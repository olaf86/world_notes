import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_notes/core/theme/note_themes.dart';
import 'package:world_notes/domain/entities/note_theme.dart';
import 'package:world_notes/presentation/widgets/note/note_theme_motion_background.dart';

void main() {
  testWidgets('keeps the standard theme free of decorative objects', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: NoteThemeMotionBackground(
            themeId: NoteThemeId.standard,
            palette: NoteThemes.of(NoteThemeId.standard).light,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is NoteThemeMotionPainter,
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('note-theme-motion-standard')),
      findsNothing,
    );
  });

  testWidgets('provides a decorative layer for every expressive theme', (
    tester,
  ) async {
    await tester.runAsync(NoteThemeShaderProgram.load);

    for (final themeId in NoteThemeId.values.where(
      (id) => id != NoteThemeId.standard,
    )) {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 480,
            child: NoteThemeMotionBackground(
              themeId: themeId,
              palette: NoteThemes.of(themeId).light,
              animate: false,
            ),
          ),
        ),
      );

      expect(
        find.byKey(ValueKey('note-theme-motion-${themeId.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('loads the shared fragment program for expressive themes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: NoteThemeMotionBackground(
            themeId: NoteThemeId.citrus,
            palette: NoteThemes.of(NoteThemeId.citrus).light,
            animate: false,
          ),
        ),
      ),
    );

    await tester.runAsync(NoteThemeShaderProgram.load);
    await tester.pumpAndSettle();

    expect(_painter(tester, NoteThemeId.citrus).fragmentShader, isNotNull);
  });

  testWidgets('renders matching endpoints for a seamless shader loop', (
    tester,
  ) async {
    final program = await tester.runAsync(NoteThemeShaderProgram.load);
    expect(program, isNotNull);
    final loadedProgram = program!;

    for (final themeId in NoteThemeId.values.where(
      (id) => id != NoteThemeId.standard,
    )) {
      final frames = await tester.runAsync(() async {
        final first = await _renderShaderFrame(loadedProgram, themeId, 0);
        final last = await _renderShaderFrame(loadedProgram, themeId, 1);
        return (first, last);
      });
      expect(frames, isNotNull);
      final renderedFrames = frames!;

      var maximumChannelDelta = 0;
      for (var index = 0; index < renderedFrames.$1.length; index++) {
        final delta = (renderedFrames.$1[index] - renderedFrames.$2[index])
            .abs();
        if (delta > maximumChannelDelta) maximumChannelDelta = delta;
      }
      expect(
        maximumChannelDelta,
        lessThanOrEqualTo(1),
        reason: '${themeId.name} must not jump when progress wraps to zero',
      );
    }
  });

  testWidgets('moves neon line crossings over time', (tester) async {
    final program = await tester.runAsync(NoteThemeShaderProgram.load);
    expect(program, isNotNull);

    final frames = await tester.runAsync(() async {
      final first = await _renderShaderFrame(program!, NoteThemeId.neon, 0);
      final second = await _renderShaderFrame(program, NoteThemeId.neon, 0.25);
      return (first, second);
    });
    expect(frames, isNotNull);

    var changedPixels = 0;
    for (var index = 0; index < frames!.$1.length; index += 4) {
      final redDelta = (frames.$1[index] - frames.$2[index]).abs();
      final greenDelta = (frames.$1[index + 1] - frames.$2[index + 1]).abs();
      final blueDelta = (frames.$1[index + 2] - frames.$2[index + 2]).abs();
      final alphaDelta = (frames.$1[index + 3] - frames.$2[index + 3]).abs();
      if (redDelta > 2 || greenDelta > 2 || blueDelta > 2 || alphaDelta > 2) {
        changedPixels++;
      }
    }

    expect(
      changedPixels,
      greaterThan(200),
      reason: 'the line families and their glowing crossings should migrate',
    );
  });

  testWidgets('uses a still composition when reduced motion is requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox(
            width: 320,
            height: 480,
            child: NoteThemeMotionBackground(
              themeId: NoteThemeId.aurora,
              palette: NoteThemes.of(NoteThemeId.aurora).light,
            ),
          ),
        ),
      ),
    );

    final before = _painter(tester, NoteThemeId.aurora).progress;
    await tester.pump(const Duration(seconds: 5));
    final after = _painter(tester, NoteThemeId.aurora).progress;

    expect(after, before);
  });

  testWidgets('advances the composition when motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: NoteThemeMotionBackground(
            themeId: NoteThemeId.botanical,
            palette: NoteThemes.of(NoteThemeId.botanical).light,
          ),
        ),
      ),
    );

    final before = _painter(tester, NoteThemeId.botanical).progress;
    await tester.pump(const Duration(seconds: 5));
    final after = _painter(tester, NoteThemeId.botanical).progress;

    expect(after, isNot(before));
  });

  testWidgets('moves far enough to read as animated within two seconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: NoteThemeMotionBackground(
            themeId: NoteThemeId.neon,
            palette: NoteThemes.of(NoteThemeId.neon).dark,
          ),
        ),
      ),
    );

    final before = _painter(tester, NoteThemeId.neon).progress;
    await tester.pump(const Duration(seconds: 2));
    final after = _painter(tester, NoteThemeId.neon).progress;

    expect((after - before).abs(), greaterThan(0.1));
  });

  testWidgets('keeps its procedural random seed stable while animating', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: NoteThemeMotionBackground(
            themeId: NoteThemeId.neon,
            palette: NoteThemes.of(NoteThemeId.neon).light,
          ),
        ),
      ),
    );

    final before = _painter(tester, NoteThemeId.neon).shaderSeed;
    await tester.pump(const Duration(seconds: 5));
    final after = _painter(tester, NoteThemeId.neon).shaderSeed;

    expect(before, inInclusiveRange(0.0, 1.0));
    expect(after, before);
  });
}

NoteThemeMotionPainter _painter(WidgetTester tester, NoteThemeId themeId) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(ValueKey('note-theme-motion-${themeId.name}')),
  );
  return paint.painter! as NoteThemeMotionPainter;
}

Future<Uint8List> _renderShaderFrame(
  ui.FragmentProgram program,
  NoteThemeId themeId,
  double progress,
) async {
  const width = 64;
  const height = 96;
  const size = Size(64, 96);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final shader = program.fragmentShader();
  NoteThemeMotionPainter(
    themeId: themeId,
    palette: NoteThemes.of(themeId).light,
    progress: progress,
    shaderSeed: 0.314159,
    opacityScale: 1,
    fragmentShader: shader,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = Uint8List.fromList(
    byteData!.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    ),
  );
  image.dispose();
  picture.dispose();
  shader.dispose();
  return bytes;
}
