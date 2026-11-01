import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oshi/features/capture/crop_screen.dart';

/// Hosts [CropScreen] behind a button so the test can capture the value the
/// route pops with.
class _CropLauncher extends StatelessWidget {
  const _CropLauncher({required this.path, required this.onResult});

  final String path;
  final ValueChanged<Uint8List?> onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<Uint8List>(
              MaterialPageRoute<Uint8List>(
                builder: (_) => CropScreen(screenshotPath: path),
              ),
            );
            onResult(result);
          },
          child: const Text('Open crop'),
        ),
      ),
    );
  }
}

Future<Uint8List> _makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEFEFEF));
  canvas.drawRect(
    Rect.fromLTWH(10, 10, width - 20, height - 20),
    Paint()..color = const Color(0xFF303030),
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG encode failed');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// Writes a generated screenshot to a temp file. Real IO and engine image
/// calls must run through [WidgetTester.runAsync] in widget tests.
Future<File> _writeScreenshot(
  WidgetTester tester, {
  int width = 400,
  int height = 300,
}) async {
  final result = await tester.runAsync(() async {
    final png = await _makePng(width, height);
    final directory = await Directory.systemTemp.createTemp(
      'oshi_crop_widget_test',
    );
    final file = File('${directory.path}/screenshot.png');
    await file.writeAsBytes(png, flush: true);
    return (directory, file);
  });
  final (directory, file) = result!;
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return file;
}

/// Pumps real asynchronous work (file IO, engine image calls) alongside fake
/// test frames until [condition] holds.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 100,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<Size> _decodeSize(WidgetTester tester, Uint8List bytes) async {
  final size = await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        return Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  });
  return size!;
}

void main() {
  testWidgets('dragging a new selection and tapping Use pops an upscaled PNG', (
    tester,
  ) async {
    final file = await _writeScreenshot(tester);

    Uint8List? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: _CropLauncher(
          path: file.path,
          onResult: (bytes) => popped = bytes,
        ),
      ),
    );

    await tester.tap(find.text('Open crop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The screenshot is decoded off the initial frame; wait for it.
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );
    expect(find.text('Drag to select text'), findsOneWidget);

    final useBefore = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use'),
    );
    expect(
      useBefore.onPressed,
      isNotNull,
      reason: 'the default selection is valid',
    );

    // Start outside the default ~80% selection, in the left strip, and drag
    // out a 200x200 logical-pixel rectangle.
    await tester.dragFrom(const Offset(20, 300), const Offset(200, 200));
    await tester.pump();

    await tester.tap(find.text('Use'));

    // Export is asynchronous (picture rasterisation + PNG encode).
    await _pumpUntil(tester, () => popped != null);
    expect(popped, isNotNull, reason: 'Use should pop PNG bytes');

    final decoded = await _decodeSize(tester, popped!);

    // 200x200 logical px at scale 0.5 -> 100x100 image px; narrower than 800,
    // so the export is 2x = 200x200.
    expect(decoded.width, 200);
    expect(decoded.height, 200);
  });

  testWidgets('Use is disabled while a new selection is below the minimum', (
    tester,
  ) async {
    final file = await _writeScreenshot(tester);

    await tester.pumpWidget(
      MaterialApp(home: CropScreen(screenshotPath: file.path)),
    );
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );

    // A tiny drag outside the selection creates a sub-minimum rect.
    final gesture = await tester.startGesture(const Offset(5, 550));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(0, 5));
    await tester.pump();

    final during = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use'),
    );
    expect(during.onPressed, isNull);

    // Releasing restores the previous (valid) selection.
    await gesture.up();
    await tester.pump();
    final after = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use'),
    );
    expect(after.onPressed, isNotNull);
  });

  testWidgets('moving the selection keeps it clamped on screen', (
    tester,
  ) async {
    final file = await _writeScreenshot(tester, width: 800, height: 600);

    await tester.pumpWidget(
      MaterialApp(home: CropScreen(screenshotPath: file.path)),
    );
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );

    // Drag from the middle of the default selection far past the left edge.
    // It moves, clamps and does not throw.
    await tester.dragFrom(const Offset(400, 300), const Offset(-1000, -1000));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final use = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use'),
    );
    expect(use.onPressed, isNotNull);
  });

  testWidgets('wide crops export at image resolution without upscaling', (
    tester,
  ) async {
    final file = await _writeScreenshot(tester, width: 2000, height: 1000);

    Uint8List? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: _CropLauncher(
          path: file.path,
          onResult: (bytes) => popped = bytes,
        ),
      ),
    );
    await tester.tap(find.text('Open crop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );

    // Default selection is 640x400 logical px of an 800x400 drawn image; at
    // scale 2.5 that is 1600x1000 image px, i.e. wider than the 800 px
    // upscale threshold, so the export keeps its resolution.
    await tester.tap(find.text('Use'));
    await _pumpUntil(tester, () => popped != null);

    final decoded = await _decodeSize(tester, popped!);
    expect(decoded.width, 1600);
    expect(decoded.height, 1000);
  });

  testWidgets('rotation keeps a valid selection and does not throw', (
    tester,
  ) async {
    final file = await _writeScreenshot(tester, width: 800, height: 600);

    await tester.pumpWidget(
      MaterialApp(home: CropScreen(screenshotPath: file.path)),
    );
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );

    await tester.dragFrom(const Offset(20, 300), const Offset(200, 100));
    await tester.pump();

    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final use = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use'),
    );
    expect(use.onPressed, isNotNull);
  });

  testWidgets('Cancel pops with null', (tester) async {
    final file = await _writeScreenshot(tester);

    var returned = false;
    Uint8List? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: _CropLauncher(
          path: file.path,
          onResult: (bytes) {
            returned = true;
            popped = bytes;
          },
        ),
      ),
    );
    await tester.tap(find.text('Open crop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpUntil(
      tester,
      () => find.text('Drag to select text').evaluate().isNotEmpty,
    );

    await tester.tap(find.text('Cancel'));
    await _pumpUntil(tester, () => returned);

    expect(returned, isTrue);
    expect(popped, isNull);
  });

  testWidgets('missing screenshot shows a friendly error with Cancel', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CropScreen(screenshotPath: '/definitely/not/here/shot.png'),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text("Couldn't open the screenshot").evaluate().isNotEmpty,
    );

    expect(find.text("Couldn't open the screenshot"), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
