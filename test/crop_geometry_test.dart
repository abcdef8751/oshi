import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:oshi/features/capture/crop_geometry.dart';

void main() {
  group('rectFromPoints', () {
    test('accepts every drag direction', () {
      const a = Offset(10, 20);
      const b = Offset(110, 220);
      const expected = Rect.fromLTRB(10, 20, 110, 220);

      expect(rectFromPoints(a, b), expected); // down-right
      expect(rectFromPoints(b, a), expected); // up-left
      expect(
        rectFromPoints(const Offset(110, 20), const Offset(10, 220)),
        expected,
      ); // down-left
      expect(
        rectFromPoints(const Offset(10, 220), const Offset(110, 20)),
        expected,
      ); // up-right
    });

    test('a zero-length drag is an empty rect at the point', () {
      const point = Offset(42, 24);
      final rect = rectFromPoints(point, point);
      expect(rect, const Rect.fromLTWH(42, 24, 0, 0));
      expect(rect.isEmpty, isTrue);
    });
  });

  group('clampSelection', () {
    const bounds = Size(500, 400);

    test('leaves a rect inside the bounds untouched', () {
      const rect = Rect.fromLTWH(100, 50, 200, 150);
      expect(clampSelection(rect, bounds), rect);
    });

    test('shrinks an oversized rect to the bounds', () {
      const rect = Rect.fromLTWH(-40, -40, 900, 900);
      expect(clampSelection(rect, bounds), const Rect.fromLTWH(0, 0, 500, 400));
    });

    test('shifts a rect with negative coordinates back inside', () {
      const rect = Rect.fromLTWH(-30, -20, 100, 80);
      expect(clampSelection(rect, bounds), const Rect.fromLTWH(0, 0, 100, 80));
    });

    test('shifts a rect overflowing the right/bottom edge back inside', () {
      const rect = Rect.fromLTWH(450, 360, 100, 100);
      expect(
        clampSelection(rect, bounds),
        const Rect.fromLTWH(400, 300, 100, 100),
      );
    });

    test(
      'grows a rect smaller than the minimum (anchored at its top-left)',
      () {
        const rect = Rect.fromLTWH(100, 50, 10, 10);
        expect(
          clampSelection(rect, bounds),
          const Rect.fromLTWH(100, 50, kMinCropSize, kMinCropSize),
        );
      },
    );

    test('expands a collapsed zero-size rect', () {
      const rect = Rect.fromLTWH(300, 200, 0, 0);
      expect(
        clampSelection(rect, bounds),
        const Rect.fromLTWH(300, 200, kMinCropSize, kMinCropSize),
      );
    });

    test('never exceeds bounds smaller than the minimum', () {
      const small = Size(20, 30);
      expect(
        clampSelection(const Rect.fromLTWH(0, 0, 10, 10), small),
        const Rect.fromLTWH(0, 0, 20, 30),
      );
    });

    test('respects a custom minSize', () {
      expect(
        clampSelection(const Rect.fromLTWH(10, 10, 5, 5), bounds, minSize: 120),
        const Rect.fromLTWH(10, 10, 120, 120),
      );
    });
  });

  group('resizeSelection', () {
    const bounds = Size(500, 500);
    const selection = Rect.fromLTWH(100, 100, 200, 200);

    test('moves the top-left corner', () {
      expect(
        resizeSelection(
          selection: selection,
          handle: CropHandle.topLeft,
          delta: const Offset(-50, -50),
          bounds: bounds,
        ),
        const Rect.fromLTWH(50, 50, 250, 250),
      );
    });

    test('moves the top-right corner', () {
      expect(
        resizeSelection(
          selection: selection,
          handle: CropHandle.topRight,
          delta: const Offset(50, -50),
          bounds: bounds,
        ),
        const Rect.fromLTWH(100, 50, 250, 250),
      );
    });

    test('moves the bottom-left corner', () {
      expect(
        resizeSelection(
          selection: selection,
          handle: CropHandle.bottomLeft,
          delta: const Offset(-50, 50),
          bounds: bounds,
        ),
        const Rect.fromLTWH(50, 100, 250, 250),
      );
    });

    test('moves the bottom-right corner', () {
      expect(
        resizeSelection(
          selection: selection,
          handle: CropHandle.bottomRight,
          delta: const Offset(50, 50),
          bounds: bounds,
        ),
        const Rect.fromLTWH(100, 100, 250, 250),
      );
    });

    test('never shrinks below the minimum size', () {
      final collapsed = resizeSelection(
        selection: selection,
        handle: CropHandle.bottomRight,
        delta: const Offset(-1000, -1000),
        bounds: bounds,
      );
      expect(collapsed.width, kMinCropSize);
      expect(collapsed.height, kMinCropSize);
      expect(collapsed.topLeft, selection.topLeft);

      final collapsedTopLeft = resizeSelection(
        selection: selection,
        handle: CropHandle.topLeft,
        delta: const Offset(1000, 1000),
        bounds: bounds,
      );
      expect(collapsedTopLeft.width, kMinCropSize);
      expect(collapsedTopLeft.height, kMinCropSize);
      expect(collapsedTopLeft.bottomRight, selection.bottomRight);
    });

    test('clamps the moving corner to the bounds', () {
      expect(
        resizeSelection(
          selection: selection,
          handle: CropHandle.bottomRight,
          delta: const Offset(1000, 1000),
          bounds: bounds,
        ),
        const Rect.fromLTWH(100, 100, 400, 400),
      );
      expect(
        resizeSelection(
          selection: selection,
          handle: CropHandle.topLeft,
          delta: const Offset(-1000, -1000),
          bounds: bounds,
        ),
        const Rect.fromLTWH(0, 0, 300, 300),
      );
    });

    test('clamps a corner that would cross an edge', () {
      final rect = resizeSelection(
        selection: const Rect.fromLTWH(10, 10, 200, 200),
        handle: CropHandle.topLeft,
        delta: const Offset(-100, -100),
        bounds: bounds,
      );
      expect(rect.left, 0);
      expect(rect.top, 0);
      expect(rect.width, 210);
      expect(rect.height, 210);
    });

    test('move translates and clamps the whole selection', () {
      expect(
        resizeSelection(
          selection: selection,
          handle: CropHandle.move,
          delta: const Offset(50, 50),
          bounds: bounds,
        ),
        const Rect.fromLTWH(150, 150, 200, 200),
      );
      // Pushed past the right/bottom edge: stays inside, keeps its size.
      expect(
        resizeSelection(
          selection: selection,
          handle: CropHandle.move,
          delta: const Offset(1000, 1000),
          bounds: bounds,
        ),
        const Rect.fromLTWH(300, 300, 200, 200),
      );
      // Pushed past the left/top edge.
      expect(
        resizeSelection(
          selection: selection,
          handle: CropHandle.move,
          delta: const Offset(-1000, -1000),
          bounds: bounds,
        ),
        const Rect.fromLTWH(0, 0, 200, 200),
      );
    });

    test('move respects a custom minSize', () {
      final rect = resizeSelection(
        selection: selection,
        handle: CropHandle.move,
        delta: const Offset(-1000, -1000),
        bounds: bounds,
        minSize: 100,
      );
      expect(rect, const Rect.fromLTWH(0, 0, 200, 200));
    });
  });

  group('upscale decision', () {
    test('threshold is strictly below 800', () {
      expect(shouldUpscale(100), isTrue);
      expect(shouldUpscale(799.9), isTrue);
      expect(shouldUpscale(800), isFalse);
      expect(shouldUpscale(800.1), isFalse);
      expect(shouldUpscale(2000), isFalse);
    });

    test('factor is 2 below 800 and 1 at/above', () {
      expect(upscaleFactor(1), 2);
      expect(upscaleFactor(799.9), 2);
      expect(upscaleFactor(800), 1);
      expect(upscaleFactor(1200), 1);
    });
  });

  group('CropTransform.fitContain', () {
    test('letterboxes a wide image horizontally', () {
      final transform = CropTransform.fitContain(
        const Size(400, 200),
        const Size(1000, 1000),
      );
      expect(transform.scale, closeTo(0.4, 1e-9));
      expect(transform.offset.dx, closeTo(0, 1e-9));
      expect(transform.offset.dy, closeTo(250, 1e-9));

      expect(transform.toView(Offset.zero), const Offset(0, 250));
      expect(transform.toImage(const Offset(0, 250)), Offset.zero);
      expect(
        transform.toImage(const Offset(1000, 750)),
        const Offset(400, 200),
      );
    });

    test('letterboxes a tall image vertically', () {
      final transform = CropTransform.fitContain(
        const Size(200, 400),
        const Size(1000, 1000),
      );
      expect(transform.scale, closeTo(0.4, 1e-9));
      expect(transform.offset.dx, closeTo(250, 1e-9));
      expect(transform.offset.dy, closeTo(0, 1e-9));

      expect(
        transform.toImageRect(const Rect.fromLTWH(250, 0, 500, 1000)),
        const Rect.fromLTWH(0, 0, 200, 400),
      );
      expect(
        transform.toImageRect(const Rect.fromLTWH(250, 250, 500, 500)),
        const Rect.fromLTWH(0, 100, 200, 200),
      );
    });

    test('round-trips image <-> view points for a wide image', () {
      final transform = CropTransform.fitContain(
        const Size(1600, 900),
        const Size(720, 1280),
      );
      for (final point in const [
        Offset.zero,
        Offset(800, 450),
        Offset(1599, 899),
      ]) {
        final roundTrip = transform.toImage(transform.toView(point));
        expect(roundTrip.dx, closeTo(point.dx, 1e-6));
        expect(roundTrip.dy, closeTo(point.dy, 1e-6));
      }
    });

    test('round-trips image <-> view points for a tall image', () {
      final transform = CropTransform.fitContain(
        const Size(900, 1600),
        const Size(1280, 720),
      );
      for (final point in const [
        Offset.zero,
        Offset(450, 800),
        Offset(899, 1599),
      ]) {
        final roundTrip = transform.toImage(transform.toView(point));
        expect(roundTrip.dx, closeTo(point.dx, 1e-6));
        expect(roundTrip.dy, closeTo(point.dy, 1e-6));
      }
    });

    test('matches a viewport with the same aspect ratio', () {
      final transform = CropTransform.fitContain(
        const Size(400, 300),
        const Size(800, 600),
      );
      expect(transform.scale, closeTo(0.5, 1e-9));
      expect(transform.offset, Offset.zero);
      expect(
        transform.toImageRect(const Rect.fromLTWH(100, 100, 200, 400)),
        const Rect.fromLTWH(50, 50, 100, 200),
      );
    });

    test('degenerate sizes fall back to an identity transform', () {
      const identity = CropTransform(scale: 1, offset: Offset.zero);
      expect(
        CropTransform.fitContain(Size.zero, const Size(100, 100)).scale,
        identity.scale,
      );
      expect(
        CropTransform.fitContain(const Size(100, 100), Size.zero).offset,
        Offset.zero,
      );
      expect(identity.toImage(const Offset(5, 6)), const Offset(5, 6));
      expect(identity.toView(const Offset(5, 6)), const Offset(5, 6));
    });
  });
}
