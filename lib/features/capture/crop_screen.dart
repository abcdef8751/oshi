import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'crop_geometry.dart';
import 'crop_overlay.dart';

/// Full-screen crop picker for a captured screenshot.
///
/// Push it as a route and await the result:
///
/// ```dart
/// final png = await Navigator.push<Uint8List>(
///   context,
///   MaterialPageRoute(builder: (_) => CropScreen(screenshotPath: path)),
/// );
/// ```
///
/// The route pops a PNG of the selection, or `null` when the user cancels.
class CropScreen extends StatefulWidget {
  const CropScreen({
    super.key,
    required this.screenshotPath,
    this.upscaleThreshold = 800,
  });

  /// Path to the frozen screenshot PNG to crop.
  final String screenshotPath;

  /// Crops narrower than this many image pixels are exported at 2x.
  final double upscaleThreshold;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  /// Longest edge the screenshot is decoded at. Keeps very large captures
  /// (panoramas, high-DPI tablets) from blowing up memory; screenshots are
  /// normally well below this.
  /// Decode cap, above current phone resolutions (e.g. 1440x3200) so the crop
  /// always works on real device pixels; only absurd inputs are resampled.
  static const int _maxDecodeEdge = 4096;

  /// Hard cap for exported images, also when no upscale was requested.
  static const int _maxOutputEdge = 4096;

  /// Hit slop around each corner handle, in logical pixels.
  static const double _handleSlop = 24;

  ui.Image? _image;
  Object? _loadError;
  bool _exporting = false;

  /// Last laid-out size of the drawn image in viewport pixels.
  Size? _imageArea;
  CropTransform? _transform;

  /// Selection in "image area" coordinates: origin at the top-left of the
  /// drawn image, one unit per logical pixel. Independent of letterboxing and
  /// stable across rotation via [_syncSelection].
  Rect? _selection;

  CropHandle? _activeHandle;
  Offset? _panDownPosition;
  Offset? _dragStart;
  Rect? _dragStartSelection;
  bool _creating = false;
  Rect? _selectionBeforeCreate;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final image = await _decodeScreenshot(widget.screenshotPath);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  /// Decodes the screenshot exactly once, capped to [_maxDecodeEdge] on the
  /// longest edge while preserving the aspect ratio.
  Future<ui.Image> _decodeScreenshot(String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('Screenshot file is empty');
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      int? targetWidth;
      int? targetHeight;
      final longest = math.max(descriptor.width, descriptor.height);
      if (longest > _maxDecodeEdge) {
        final ratio = _maxDecodeEdge / longest;
        targetWidth = math.max(1, (descriptor.width * ratio).round());
        targetHeight = math.max(1, (descriptor.height * ratio).round());
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  Offset get _imageOffset => _transform?.offset ?? Offset.zero;

  bool get _hasValidSelection {
    final selection = _selection;
    return selection != null &&
        selection.width >= kMinCropSize &&
        selection.height >= kMinCropSize;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) return _buildError(context);

    final image = _image;
    if (image == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [_buildLoading(), _buildTopBar(context)],
        ),
      );
    }

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final transform = CropTransform.fitContain(imageSize, viewport);
          final imageArea = Size(
            imageSize.width / transform.scale,
            imageSize.height / transform.scale,
          );

          // Runs during layout, so the bars built below always see the
          // selection for this viewport size.
          _syncSelection(transform, imageArea, viewport);
          final viewportSelection = _selection?.shift(transform.offset);

          return Stack(
            fit: StackFit.expand,
            children: [
              RawImage(
                image: image,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
              CropOverlay(
                selection: viewportSelection,
                onPanDown: _onPanDown,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
              ),
              _buildTopBar(context),
              _buildBottomHint(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppTheme.accent,
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: Colors.white54,
              ),
              const SizedBox(height: 16),
              const Text(
                "Couldn't open the screenshot",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'The capture may have been deleted. Take a fresh screenshot and try again.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: const Color(0xFF11101A),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Recomputes the selection for the current layout.
  ///
  /// On the first layout a centred rectangle covering ~80% of the viewport is
  /// used (clamped to the drawn image and to [kMinCropSize]). When the layout
  /// size changes — rotation, window resize — the selection is scaled with the
  /// drawn image so it keeps covering the same part of the screenshot.
  void _syncSelection(CropTransform transform, Size imageArea, Size viewport) {
    final previousArea = _imageArea;
    final previousSelection = _selection;

    _transform = transform;
    _imageArea = imageArea;

    var selection = previousSelection;
    if (selection != null &&
        previousArea != null &&
        previousArea.width > 0 &&
        previousArea.height > 0 &&
        previousArea != imageArea) {
      final scaleX = imageArea.width / previousArea.width;
      final scaleY = imageArea.height / previousArea.height;
      selection = Rect.fromLTRB(
        selection.left * scaleX,
        selection.top * scaleY,
        selection.right * scaleX,
        selection.bottom * scaleY,
      );
    }

    selection ??= Rect.fromCenter(
      center: imageArea.center(Offset.zero),
      width: viewport.width * 0.8,
      height: viewport.height * 0.8,
    );

    // While a brand-new rect is being dragged it is allowed to be smaller than
    // the minimum; the drag-end handler restores/validates it.
    _selection = clampSelection(
      selection,
      imageArea,
      minSize: _creating ? 0 : kMinCropSize,
    );
  }

  void _onPanDown(Offset localPosition) {
    _panDownPosition = localPosition;
  }

  void _onPanStart(Offset localPosition) {
    final selection = _selection;
    final imageArea = _imageArea;
    if (selection == null || imageArea == null) return;

    // Prefer the true pointer-down position for hit testing and for the anchor
    // of a brand-new rectangle: pan recognisers only report the start after
    // the touch slop has been consumed. An existing corner is dragged from the
    // recognised position instead, so it does not jump by the slop.
    final down = _panDownPosition ?? localPosition;
    final offset = _imageOffset;

    _activeHandle = _hitTest(down, selection.shift(offset));

    if (_activeHandle == null) {
      _creating = true;
      _dragStart = down;
      _selectionBeforeCreate = selection;
      setState(() {
        _selection = clampSelection(
          rectFromPoints(down, down).shift(-offset),
          imageArea,
          minSize: 0,
        );
      });
    } else {
      _creating = false;
      _dragStart = localPosition;
      _dragStartSelection = selection;
    }
  }

  CropHandle? _hitTest(Offset point, Rect viewportSelection) {
    bool near(Offset corner) => (point - corner).distance <= _handleSlop;

    if (near(viewportSelection.topLeft)) return CropHandle.topLeft;
    if (near(viewportSelection.topRight)) return CropHandle.topRight;
    if (near(viewportSelection.bottomLeft)) return CropHandle.bottomLeft;
    if (near(viewportSelection.bottomRight)) return CropHandle.bottomRight;
    if (viewportSelection.contains(point)) return CropHandle.move;
    return null;
  }

  void _onPanUpdate(Offset localPosition) {
    final start = _dragStart;
    final imageArea = _imageArea;
    if (start == null || imageArea == null) return;
    final offset = _imageOffset;

    if (_creating) {
      final from = start - offset;
      final to = localPosition - offset;
      setState(() {
        _selection = clampSelection(
          rectFromPoints(from, to),
          imageArea,
          minSize: 0,
        );
      });
      return;
    }

    final handle = _activeHandle;
    final base = _dragStartSelection;
    if (handle == null || base == null) return;

    setState(() {
      _selection = resizeSelection(
        selection: base,
        handle: handle,
        delta: localPosition - start,
        bounds: imageArea,
      );
    });
  }

  void _onPanEnd() {
    final imageArea = _imageArea;

    if (_creating) {
      final selection = _selection;
      final tooSmall =
          selection == null ||
          selection.width < kMinCropSize ||
          selection.height < kMinCropSize;
      if (tooSmall) {
        // A tap / accidental flick outside the selection restores the previous
        // one instead of leaving an unusable sliver.
        _selection = _selectionBeforeCreate;
      } else if (imageArea != null) {
        _selection = clampSelection(selection, imageArea);
      }
      _creating = false;
      _selectionBeforeCreate = null;
      setState(() {});
    }

    _activeHandle = null;
    _dragStartSelection = null;
    _dragStart = null;
    _panDownPosition = null;
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  Future<void> _useSelection() async {
    final image = _image;
    final selection = _selection;
    final transform = _transform;
    if (image == null ||
        selection == null ||
        transform == null ||
        _exporting ||
        !_hasValidSelection) {
      return;
    }

    setState(() => _exporting = true);
    try {
      final bytes = await _exportPng(
        image: image,
        viewportSelection: selection.shift(transform.offset),
        transform: transform,
      );
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } catch (error) {
      if (!mounted) return;
      setState(() => _exporting = false);
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text("Couldn't export the crop. Try a smaller selection."),
        ),
      );
    }
  }

  /// Crops [viewportSelection] out of [image] at image resolution, upscales it
  /// 2x with cubic filtering when it is narrower than
  /// [CropScreen.upscaleThreshold], and PNG-encodes the result.
  Future<Uint8List> _exportPng({
    required ui.Image image,
    required Rect viewportSelection,
    required CropTransform transform,
  }) async {
    final imageRect = transform.toImageRect(viewportSelection);

    final left = math.max(0, math.min(image.width - 1, imageRect.left.round()));
    final top = math.max(0, math.min(image.height - 1, imageRect.top.round()));
    final right = math.max(
      left + 1,
      math.min(image.width, imageRect.right.round()),
    );
    final bottom = math.max(
      top + 1,
      math.min(image.height, imageRect.bottom.round()),
    );

    final sourceWidth = right - left;
    final sourceHeight = bottom - top;

    final upscale = upscaleFactor(
      sourceWidth.toDouble(),
      threshold: widget.upscaleThreshold,
    );
    var outputWidth = sourceWidth * upscale;
    var outputHeight = sourceHeight * upscale;

    final longestEdge = math.max(outputWidth, outputHeight);
    if (longestEdge > _maxOutputEdge) {
      final ratio = _maxOutputEdge / longestEdge;
      outputWidth = math.max(1, (outputWidth * ratio).floor());
      outputHeight = math.max(1, (outputHeight * ratio).floor());
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        sourceWidth.toDouble(),
        sourceHeight.toDouble(),
      ),
      Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
      // Cubic-ish resampling for the 2x OCR upscale.
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    try {
      final output = await picture.toImage(outputWidth, outputHeight);
      try {
        final data = await output.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('PNG encoding returned no data');
        }
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        output.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  Widget _buildTopBar(BuildContext context) {
    final canUse = _hasValidSelection && _image != null && !_exporting;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _BarChip(
                child: TextButton(
                  onPressed: _cancel,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const Spacer(),
              _BarChip(
                child: FilledButton(
                  onPressed: canUse ? _useSelection : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: const Color(0xFF11101A),
                    disabledBackgroundColor: Colors.white24,
                    disabledForegroundColor: Colors.white38,
                    minimumSize: const Size(72, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF11101A),
                          ),
                        )
                      : const Text('Use'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomHint() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Drag to select text',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark translucent pill that keeps the controls readable over light
/// screenshots.
class _BarChip extends StatelessWidget {
  const _BarChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
