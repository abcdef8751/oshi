import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The interaction and painting layer of the crop screen.
///
/// Sits on top of the full-bleed screenshot, dims everything outside the
/// selection, draws the accent border and the four corner handles, and turns
/// pan gestures into plain viewport-local positions for [CropScreen] to
/// interpret.
class CropOverlay extends StatelessWidget {
  const CropOverlay({
    super.key,
    required this.selection,
    required this.onPanDown,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  /// Selection rectangle in viewport-local coordinates, or null when there is
  /// nothing selected (only the dim layer is painted).
  ///
  /// A listenable rather than a plain value so dragging repaints only the
  /// overlay instead of rebuilding (and repainting the screenshot).
  final ValueListenable<Rect?> selection;

  /// The initial pointer-down position. Reported separately from
  /// [onPanStart] because gesture recognisers swallow a few pixels of touch
  /// slop before the pan starts; starting from the real down point avoids a
  /// visible jump.
  final ValueChanged<Offset> onPanDown;
  final ValueChanged<Offset> onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (details) => onPanDown(details.localPosition),
      onPanStart: (details) => onPanStart(details.localPosition),
      onPanUpdate: (details) => onPanUpdate(details.localPosition),
      onPanEnd: (_) => onPanEnd(),
      onPanCancel: onPanEnd,
      child: CustomPaint(
        painter: CropOverlayPainter(selection: selection),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Paints the dim layer, selection border and corner handles.
class CropOverlayPainter extends CustomPainter {
  CropOverlayPainter({required this.selection}) : super(repaint: selection);

  final ValueListenable<Rect?> selection;

  static const Color dimColor = Color(0x99000000);
  static const double handleArm = 22;
  static const double handleStroke = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final dimPaint = Paint()..color = dimColor;
    final selected = selection.value;

    if (selected == null || selected.width <= 0 || selected.height <= 0) {
      canvas.drawRect(full, dimPaint);
      return;
    }

    final clipped = selected.intersect(full);
    if (clipped.isEmpty) {
      canvas.drawRect(full, dimPaint);
      return;
    }

    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      Path()..addRect(clipped),
    );
    canvas.drawPath(outside, dimPaint);

    final borderPaint = Paint()
      ..color = AppTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(clipped, borderPaint);

    final handlePaint = Paint()
      ..color = AppTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = handleStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final arm = handleArm;
    _corner(canvas, handlePaint, clipped.topLeft, 1, 1, arm);
    _corner(canvas, handlePaint, clipped.topRight, -1, 1, arm);
    _corner(canvas, handlePaint, clipped.bottomLeft, 1, -1, arm);
    _corner(canvas, handlePaint, clipped.bottomRight, -1, -1, arm);
  }

  void _corner(
    Canvas canvas,
    Paint paint,
    Offset corner,
    double xDirection,
    double yDirection,
    double arm,
  ) {
    final horizontal = corner.translate(xDirection * arm, 0);
    final vertical = corner.translate(0, yDirection * arm);
    final path = Path()
      ..moveTo(horizontal.dx, horizontal.dy)
      ..lineTo(corner.dx, corner.dy)
      ..lineTo(vertical.dx, vertical.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) =>
      oldDelegate.selection != selection;
}
