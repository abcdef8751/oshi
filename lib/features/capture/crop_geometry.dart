import 'dart:math' as math;
import 'dart:ui';

/// Smallest crop a selection may have, in logical pixels.
const double kMinCropSize = 48;

/// Which part of the selection a drag is manipulating.
enum CropHandle { topLeft, topRight, bottomLeft, bottomRight, move }

/// Builds a normalized rectangle from two arbitrary points.
///
/// Handles inverted drags: dragging from bottom-right to top-left produces the
/// same rectangle as the opposite direction.
Rect rectFromPoints(Offset a, Offset b) {
  return Rect.fromLTRB(
    math.min(a.dx, b.dx),
    math.min(a.dy, b.dy),
    math.max(a.dx, b.dx),
    math.max(a.dy, b.dy),
  );
}

/// Clamps [rect] into `0,0` – [bounds], growing it to [minSize] where needed.
///
/// * A rect inside the bounds is returned unchanged.
/// * An oversized rect is shrunk to the bounds (anchored at its top-left).
/// * A rect with negative coordinates keeps its size but is shifted inside.
/// * A rect smaller than [minSize] is grown (anchored at its top-left), unless
///   the bounds themselves are smaller, in which case they win.
Rect clampSelection(Rect rect, Size bounds, {double minSize = kMinCropSize}) {
  final normalized = rectFromPoints(rect.topLeft, rect.bottomRight);
  final boundWidth = math.max(0.0, bounds.width);
  final boundHeight = math.max(0.0, bounds.height);
  final min = math.max(0.0, minSize);

  final width = math.min(math.max(normalized.width, min), boundWidth);
  final height = math.min(math.max(normalized.height, min), boundHeight);

  final left = normalized.left
      .clamp(0.0, math.max(0.0, boundWidth - width))
      .toDouble();
  final top = normalized.top
      .clamp(0.0, math.max(0.0, boundHeight - height))
      .toDouble();

  return Rect.fromLTWH(left, top, width, height);
}

/// Resizes [selection] by [delta] according to [handle].
///
/// Corner handles move one corner while the opposite corner stays anchored;
/// [CropHandle.move] translates the whole selection. The result stays inside
/// [bounds] and never gets smaller than [minSize] on either axis.
Rect resizeSelection({
  required Rect selection,
  required CropHandle handle,
  required Offset delta,
  required Size bounds,
  double minSize = kMinCropSize,
}) {
  final normalized = rectFromPoints(selection.topLeft, selection.bottomRight);
  if (handle == CropHandle.move) {
    return clampSelection(normalized.shift(delta), bounds, minSize: minSize);
  }

  final boundWidth = math.max(0.0, bounds.width);
  final boundHeight = math.max(0.0, bounds.height);
  final min = math.max(0.0, minSize);

  var left = normalized.left.clamp(0.0, boundWidth).toDouble();
  var top = normalized.top.clamp(0.0, boundHeight).toDouble();
  var right = normalized.right.clamp(0.0, boundWidth).toDouble();
  var bottom = normalized.bottom.clamp(0.0, boundHeight).toDouble();

  // Clamp a moving edge between two limits. Callers build the limits so that
  // `lower <= upper`; when the bounds are smaller than minSize the two limits
  // collapse and the moving edge parks on them.
  double edge(double value, double lower, double upper) {
    return value.clamp(lower, math.max(lower, upper)).toDouble();
  }

  switch (handle) {
    case CropHandle.topLeft:
      left = edge(left + delta.dx, 0.0, math.max(0.0, right - min));
      top = edge(top + delta.dy, 0.0, math.max(0.0, bottom - min));
    case CropHandle.topRight:
      right = edge(
        right + delta.dx,
        math.min(boundWidth, left + min),
        boundWidth,
      );
      top = edge(top + delta.dy, 0.0, math.max(0.0, bottom - min));
    case CropHandle.bottomLeft:
      left = edge(left + delta.dx, 0.0, math.max(0.0, right - min));
      bottom = edge(
        bottom + delta.dy,
        math.min(boundHeight, top + min),
        boundHeight,
      );
    case CropHandle.bottomRight:
      right = edge(
        right + delta.dx,
        math.min(boundWidth, left + min),
        boundWidth,
      );
      bottom = edge(
        bottom + delta.dy,
        math.min(boundHeight, top + min),
        boundHeight,
      );
    case CropHandle.move:
      break; // handled above
  }

  return Rect.fromLTRB(left, top, right, bottom);
}

/// Whether a crop of [cropWidth] image pixels is small enough to upscale 2x.
bool shouldUpscale(double cropWidth) => cropWidth < 800;

/// The upscale factor for a crop of [cropWidth] image pixels: 2 or 1.
int upscaleFactor(double cropWidth) => shouldUpscale(cropWidth) ? 2 : 1;

/// Maps between image pixels and viewport coordinates for a `BoxFit.contain`
/// letterboxed image.
class CropTransform {
  const CropTransform({required this.scale, required this.offset});

  /// Image pixels per logical pixel.
  ///
  /// A value of `0.5` means one logical pixel covers half an image pixel, i.e.
  /// the image is drawn at twice its natural size. `1 / scale` is the familiar
  /// `BoxFit` factor (logical pixels per image pixel).
  final double scale;

  /// Top-left corner of the drawn image inside the viewport.
  final Offset offset;

  /// Maps a viewport-local point to image pixel coordinates.
  Offset toImage(Offset local) => (local - offset) * scale;

  /// Maps image pixel coordinates to a viewport-local point.
  Offset toView(Offset image) {
    if (scale == 0) return offset;
    return offset + image / scale;
  }

  /// Maps a viewport-local rectangle to image pixel coordinates.
  Rect toImageRect(Rect viewRect) {
    return Rect.fromPoints(
      toImage(viewRect.topLeft),
      toImage(viewRect.bottomRight),
    );
  }

  /// Builds the transform that draws [image] inside [viewport] with
  /// `BoxFit.contain`, centred on both axes.
  static CropTransform fitContain(Size image, Size viewport) {
    if (image.width <= 0 ||
        image.height <= 0 ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return const CropTransform(scale: 1, offset: Offset.zero);
    }
    final scale = math.max(
      image.width / viewport.width,
      image.height / viewport.height,
    );
    final drawnWidth = image.width / scale;
    final drawnHeight = image.height / scale;
    return CropTransform(
      scale: scale,
      offset: Offset(
        (viewport.width - drawnWidth) / 2,
        (viewport.height - drawnHeight) / 2,
      ),
    );
  }
}
