import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'rgba_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;

import 'editor.dart';
import 'brush_preview.dart';

class PixelCanvas extends StatefulWidget {
  const PixelCanvas({
    super.key,
    required this.editor,
    required this.tool,
    required this.color,
    required this.brush,
    required this.grid,
    required this.onion,
    required this.fitToken,
    required this.onPick,
    required this.onStroke,
    this.filled = false,
    this.mirrorX = false,
    this.mirrorY = false,
    this.density = 12,
    this.seed = 1,
    this.strength = 50,
    this.previewOptions = const {},
  });
  final Editor editor;
  final String tool;
  final int color, brush, fitToken;
  final bool grid, onion;
  final bool filled, mirrorX, mirrorY;
  final int density, seed, strength;
  final Map<String, dynamic> previewOptions;
  final ValueChanged<int> onPick;
  final FutureOr<void> Function(String, List<Offset>) onStroke;
  @override
  State<PixelCanvas> createState() => _PixelCanvasState();
}

class _PixelCanvasState extends State<PixelCanvas> {
  final Map<int, Offset> pointers = {};
  List<Offset> stroke = [];
  double scale = 1;
  Offset origin = Offset.zero;
  Size viewport = Size.zero;
  bool fitted = false, navigating = false;
  Timer? _spraying, _previewTimer;
  Duration _startedAt = Duration.zero;
  ui.Image? _preview;
  final List<_CanvasPainter> _committing = [];

  @override
  void initState() {
    super.initState();
    widget.editor.imageChanges.addListener(_imageReady);
  }

  void _imageReady() {
    // Retire the matching visual synchronously with the decoded image swap,
    // before the painter sees it. Waiting for the callback Future alone can
    // leave one frame with both the committed pixels and their alpha overlay.
    if (widget.editor.imageOperation == 'stroke') {
      if (_committing.isNotEmpty) {
        _committing.removeAt(0).preview?.dispose();
      }
    } else {
      _clearCommitting();
    }
    if (mounted) setState(() {});
  }

  void _clearCommitting() {
    for (final visual in _committing) {
      visual.preview?.dispose();
    }
    _committing.clear();
  }

  _CanvasPainter _visual(List<Offset> points, ui.Image? preview) =>
      _CanvasPainter(
        widget.editor,
        origin,
        scale,
        widget.grid,
        widget.onion,
        points,
        widget.tool,
        widget.color,
        widget.brush,
        widget.filled,
        widget.mirrorX,
        widget.mirrorY,
        widget.density,
        _strokeSeed,
        widget.strength,
        preview,
      );

  void _commit(List<Offset> points) {
    // Transfer ownership of the live preview to a retained commit visual.
    // Removing it at pointer-up exposes the previous image while the backend
    // and RGBA decoder are still busy, especially for long strokes.
    final visual = _visual(points, _preview);
    _preview = null;
    _clearPreview();
    _committing.add(visual);
    _nextSeed = (_nextSeed + 1) & 0xffffffff;
    void finish() {
      if (_committing.remove(visual)) {
        visual.preview?.dispose();
        if (mounted) setState(() {});
      }
    }

    Future<void>.sync(() => widget.onStroke(visual.tool, points)).then(
      (_) => finish(),
      onError: (Object error, StackTrace stack) => finish(),
    );
  }

  bool _previewRunning = false;
  int _previewEpoch = 0, _pointVersion = 0;
  bool get _usesPreview => const {
    'spray',
    'airbrush',
    'blur',
    'jumble',
    'gradient',
    'metal',
    'cluster',
    'stripes',
    'sphere',
    'knife',
    'ditherPaint',
    'ditherRetouch',
  }.contains(widget.tool);
  void _clearPreview() {
    _previewEpoch++;
    _previewTimer?.cancel();
    _previewTimer = null;
    _preview?.dispose();
    _preview = null;
  }

  void _schedulePreview() {
    _pointVersion++;
    if (!_usesPreview ||
        stroke.isEmpty ||
        _previewTimer != null ||
        _previewRunning) {
      return;
    }
    _previewTimer = Timer(const Duration(milliseconds: 75), _loadPreview);
  }

  Future<void> _loadPreview() async {
    _previewTimer = null;
    if (!mounted || stroke.isEmpty || navigating || !_usesPreview) return;
    if (widget.editor.busy) {
      _schedulePreview();
      return;
    }
    final epoch = _previewEpoch, version = _pointVersion;
    final width = widget.editor.width, height = widget.editor.height;
    _previewRunning = true;
    try {
      final result = await widget.editor.transport('previewStroke', {
        ...widget.previewOptions,
        'tool': widget.tool,
        'color': widget.color,
        'size': widget.brush,
        'points': stroke.map((p) => [p.dx.floor(), p.dy.floor()]).toList(),
        'seed': _strokeSeed,
        'density': widget.density,
        'strength': widget.strength,
        'mirrorX': widget.mirrorX,
        'mirrorY': widget.mirrorY,
      });
      final bytes = result?['pixels'];
      if (bytes is Uint8List && bytes.length == width * height * 4) {
        final next = await decodeStraightRgba(
          bytes,
          width: width,
          height: height,
        );
        if (!mounted || epoch != _previewEpoch || stroke.isEmpty) {
          next.dispose();
        } else {
          setState(() {
            _preview?.dispose();
            _preview = next;
          });
        }
      }
    } catch (_) {
      // Preview is optional. The authoritative commit reports any real error.
    } finally {
      _previewRunning = false;
      if (mounted && (epoch != _previewEpoch || version != _pointVersion)) {
        // A newer gesture can start while the canceled gesture's request is
        // still in flight. Restart for that gesture even if it is held still.
        _schedulePreview();
      }
    }
  }

  late int _nextSeed = widget.seed;
  late int _strokeSeed = widget.seed;
  bool get _continuous => const {'spray', 'airbrush'}.contains(widget.tool);
  void _stopSpraying() {
    _spraying?.cancel();
    _spraying = null;
  }

  void _startSpraying() {
    _stopSpraying();
    if (!_continuous) return;
    _spraying = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || navigating || pointers.length != 1 || stroke.isEmpty) {
        _stopSpraying();
        return;
      }
      // Repeated positions are intentional stamps, including a held pointer.
      if (stroke.length < 10000) {
        setState(() => stroke.add(stroke.last));
        _schedulePreview();
      }
    });
  }

  @override
  void dispose() {
    widget.editor.imageChanges.removeListener(_imageReady);
    _stopSpraying();
    _clearPreview();
    _clearCommitting();
    super.dispose();
  }

  Offset _pixel(Offset p) => (p - origin) / scale;
  Offset get centroid =>
      pointers.values.fold(Offset.zero, (a, b) => a + b) /
      pointers.length.toDouble();
  double get distance => pointers.length < 2
      ? 1
      : (pointers.values.first - pointers.values.elementAt(1)).distance;
  @override
  void didUpdateWidget(PixelCanvas old) {
    super.didUpdateWidget(old);
    if (!identical(old.editor, widget.editor)) {
      old.editor.imageChanges.removeListener(_imageReady);
      widget.editor.imageChanges.addListener(_imageReady);
    }
    if (old.fitToken != widget.fitToken) {
      _clearCommitting();
      fitted = false;
      _stopSpraying();
      _clearPreview();
      stroke.clear();
      if (pointers.isNotEmpty) navigating = true;
    }
    if (!identical(old.editor, widget.editor) ||
        (widget.editor.busy && !widget.editor.busyDrawing)) {
      _clearCommitting();
    }
    if (old.tool != widget.tool ||
        (widget.editor.busy && !widget.editor.busyDrawing) ||
        old.color != widget.color ||
        old.brush != widget.brush ||
        old.filled != widget.filled ||
        old.mirrorX != widget.mirrorX ||
        old.mirrorY != widget.mirrorY ||
        old.density != widget.density ||
        old.strength != widget.strength) {
      _stopSpraying();
      _clearPreview();
      stroke.clear();
      if (pointers.isNotEmpty) navigating = true;
    }
  }

  void down(PointerDownEvent e) {
    if (widget.editor.busy && !widget.editor.busyDrawing && pointers.isEmpty) {
      return;
    }
    // A second finger switches to navigation; it must not erase the stroke
    // already shown. Commit the existing segment exactly once before panning.
    final pending =
        pointers.length == 1 &&
            !navigating &&
            stroke.isNotEmpty &&
            (stroke.length > 1 ||
                e.timeStamp - _startedAt > const Duration(milliseconds: 150))
        ? List<Offset>.of(stroke)
        : null;
    if (pending != null && widget.tool != 'eyedropper') _commit(pending);
    setState(() {
      pointers[e.pointer] = e.localPosition;
      if (pointers.length > 1 || widget.tool == 'pan' || e.buttons == 2) {
        _stopSpraying();
        _clearPreview();
        navigating = true;
        stroke.clear();
      } else {
        navigating = false;
        _startedAt = e.timeStamp;
        stroke = [_pixel(e.localPosition)];
        _strokeSeed = _nextSeed;
        _startSpraying();
        _schedulePreview();
      }
    });
  }

  void move(PointerMoveEvent e) {
    if (!pointers.containsKey(e.pointer)) return;
    setState(() {
      final oldCenter = centroid, oldDistance = distance;
      pointers[e.pointer] = e.localPosition;
      if (navigating) {
        final newCenter = centroid;
        final next =
            (scale *
                    (pointers.length > 1 && oldDistance > 0
                        ? distance / oldDistance
                        : 1))
                .clamp(.25, 128.0)
                .toDouble();
        origin = newCenter - (oldCenter - origin) * (next / scale);
        scale = next;
      } else {
        final p = _pixel(e.localPosition);
        if (stroke.isEmpty || (stroke.last - p).distance >= .15) {
          stroke.add(p);
          _schedulePreview();
        }
      }
    });
  }

  void up(PointerEvent e, {bool cancel = false}) {
    if (!pointers.containsKey(e.pointer)) return;
    _stopSpraying();
    final points = List<Offset>.of(stroke);
    final commit =
        !cancel && !navigating && pointers.length == 1 && points.isNotEmpty;
    if (commit && widget.tool != 'eyedropper') {
      _commit(points);
    } else {
      _clearPreview();
    }
    setState(() {
      pointers.remove(e.pointer);
      stroke.clear();
      if (pointers.isEmpty) navigating = false;
    });
    if (!commit) return;
    if (widget.tool == 'eyedropper') {
      final p = points.last, bytes = widget.editor.state['pixels'];
      final x = p.dx.floor(), y = p.dy.floor();
      if (x >= 0 &&
          y >= 0 &&
          x < widget.editor.width &&
          y < widget.editor.height &&
          bytes != null) {
        final i = (y * widget.editor.width + x) * 4;
        widget.onPick(
          (bytes[i + 3] as int) << 24 |
              (bytes[i] as int) << 16 |
              (bytes[i + 1] as int) << 8 |
              bytes[i + 2],
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (!fitted || viewport != size) {
        viewport = size;
        scale = math
            .min(
              (size.width - 40) / widget.editor.width,
              (size.height - 40) / widget.editor.height,
            )
            .clamp(.25, 24.0)
            .toDouble();
        origin = Offset(
          (size.width - widget.editor.width * scale) / 2,
          (size.height - widget.editor.height * scale) / 2,
        );
        fitted = true;
      }
      return ClipRect(
        child: Listener(
          key: const Key('pixel-canvas'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: down,
          onPointerMove: move,
          onPointerUp: (e) => up(e),
          onPointerCancel: (e) => up(e, cancel: true),
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && pointers.isEmpty) {
              setState(() {
                final next = (scale * math.exp(-event.scrollDelta.dy / 400))
                    .clamp(.25, 128.0)
                    .toDouble();
                origin =
                    event.localPosition -
                    (event.localPosition - origin) * (next / scale);
                scale = next;
              });
            }
          },
          child: RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: _CanvasPainter(
                widget.editor,
                origin,
                scale,
                widget.grid,
                widget.onion,
                stroke,
                widget.tool,
                widget.color,
                widget.brush,
                widget.filled,
                widget.mirrorX,
                widget.mirrorY,
                widget.density,
                _strokeSeed,
                widget.strength,
                _preview,
                committing: _committing,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(
    this.editor,
    this.origin,
    this.scale,
    this.grid,
    this.onion,
    this.points,
    this.tool,
    this.color,
    this.brush,
    this.filled,
    this.mirrorX,
    this.mirrorY,
    this.density,
    this.seed,
    this.strength,
    this.preview, {
    this.committing = const [],
  }) : super(repaint: editor.imageChanges);
  final Editor editor;
  final ui.Image? preview;
  final List<_CanvasPainter> committing;
  final Offset origin;
  final double scale;
  final bool grid, onion;
  final List<Offset> points;
  final String tool;
  final int color, brush;
  final bool filled, mirrorX, mirrorY;
  final int density, seed, strength;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff10141d), BlendMode.src);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    final bounds = Rect.fromLTWH(
      0,
      0,
      editor.width.toDouble(),
      editor.height.toDouble(),
    );
    canvas.clipRect(bounds);
    canvas.drawRect(bounds, Paint()..color = const Color(0xffc3c6cf));
    final cell = math.max(4, (8 / scale).ceil());
    for (
      int y = math.max(0, (-origin.dy / scale / cell).floor() * cell);
      y < math.min(editor.height, (size.height - origin.dy) / scale);
      y += cell
    ) {
      for (
        int x = math.max(0, (-origin.dx / scale / cell).floor() * cell);
        x < math.min(editor.width, (size.width - origin.dx) / scale);
        x += cell
      ) {
        if ((x ~/ cell + y ~/ cell).isEven) {
          canvas.drawRect(
            Rect.fromLTWH(
              x.toDouble(),
              y.toDouble(),
              cell.toDouble(),
              cell.toDouble(),
            ),
            Paint()..color = const Color(0xff9196a3),
          );
        }
      }
    }
    final image = editor.image;
    if (onion && editor.previous != null) {
      canvas.drawImage(
        editor.previous!,
        Offset.zero,
        Paint()
          ..filterQuality = FilterQuality.none
          ..color = const Color(0x55ffffff),
      );
    }
    canvas.saveLayer(bounds, Paint());
    if (image != null) {
      canvas.drawImage(
        image,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    for (final visual in committing) {
      visual.paintStroke(canvas);
    }
    paintStroke(canvas);
    canvas.restore();
    if (mirrorX || mirrorY) {
      final p = Paint()
        ..color = const Color(0x9989a7ff)
        ..strokeWidth = 1 / scale;
      if (mirrorX) {
        canvas.drawLine(
          Offset(editor.width / 2, 0),
          Offset(editor.width / 2, editor.height.toDouble()),
          p,
        );
      }
      if (mirrorY) {
        canvas.drawLine(
          Offset(0, editor.height / 2),
          Offset(editor.width.toDouble(), editor.height / 2),
          p,
        );
      }
    }
    if (grid && scale >= 6) {
      final p = Paint()
        ..color = const Color(0x44000000)
        ..strokeWidth = 1 / scale;
      for (var x = 0; x <= editor.width; x++) {
        canvas.drawLine(
          Offset(x.toDouble(), 0),
          Offset(x.toDouble(), editor.height.toDouble()),
          p,
        );
      }
      for (var y = 0; y <= editor.height; y++) {
        canvas.drawLine(
          Offset(0, y.toDouble()),
          Offset(editor.width.toDouble(), y.toDouble()),
          p,
        );
      }
    }
    canvas.restore();
    canvas.drawRect(
      Rect.fromLTWH(
        origin.dx,
        origin.dy,
        bounds.width * scale,
        bounds.height * scale,
      ),
      Paint()
        ..color = const Color(0xff596277)
        ..style = PaintingStyle.stroke,
    );
  }

  void paintStroke(Canvas canvas) {
    if (preview != null) {
      // Effect previews contain the complete composited frame, including its
      // transparency. Replace the prior frame rather than alpha-blending it
      // twice. The checkerboard remains outside this isolated pixel layer.
      canvas.drawImage(
        preview!,
        Offset.zero,
        Paint()
          ..filterQuality = FilterQuality.none
          ..blendMode = BlendMode.src,
      );
    }
    if (preview == null &&
        points.isNotEmpty &&
        tool != 'pan' &&
        tool != 'eyedropper') {
      if (tool == 'gradient') {
        final guide = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale;
        canvas.drawLine(points.first, points.last, guide);
        for (final endpoint in [points.first, points.last]) {
          canvas.drawCircle(endpoint, 3 / scale, guide);
        }
      } else if (const {
        'fill',
        'blur',
        'jumble',
        'airbrush',
        'metal',
        'cluster',
        'stripes',
        'sphere',
        'knife',
        'ditherPaint',
        'ditherRetouch',
      }.contains(tool)) {
        final point = tool == 'fill' ? points.first : points.last;
        final p = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale;
        for (final x in [
          point.dx.floor(),
          if (mirrorX) editor.width - 1 - point.dx.floor(),
        ]) {
          for (final y in [
            point.dy.floor(),
            if (mirrorY) editor.height - 1 - point.dy.floor(),
          ]) {
            final size = tool == 'fill' ? 1 : brush;
            canvas.drawRect(
              Rect.fromLTWH(
                (x - size ~/ 2).toDouble(),
                (y - size ~/ 2).toDouble(),
                size.toDouble(),
                size.toDouble(),
              ),
              p,
            );
          }
        }
      } else {
        final runs = previewStrokeRuns(
          width: editor.width,
          height: editor.height,
          tool: tool,
          points: points,
          size: brush,
          filled: filled,
          mirrorX: mirrorX,
          mirrorY: mirrorY,
          seed: seed,
          density: density,
        );
        final p = Paint()
          ..color = tool == 'eraser' ? const Color(0x99ffffff) : Color(color)
          ..isAntiAlias = false;
        for (final run in runs) {
          canvas.drawRect(run, p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}
