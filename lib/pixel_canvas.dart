import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;

import 'editor.dart';

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
  });
  final Editor editor;
  final String tool;
  final int color, brush, fitToken;
  final bool grid, onion;
  final ValueChanged<int> onPick;
  final void Function(String, List<Offset>) onStroke;
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
    if (old.fitToken != widget.fitToken) {
      fitted = false;
      stroke.clear();
      if (pointers.isNotEmpty) navigating = true;
    }
    if (old.tool != widget.tool || widget.editor.busy) {
      stroke.clear();
      if (pointers.isNotEmpty) navigating = true;
    }
  }

  void down(PointerDownEvent e) {
    if (widget.editor.busy) return;
    setState(() {
      pointers[e.pointer] = e.localPosition;
      if (pointers.length > 1 || widget.tool == 'pan' || e.buttons == 2) {
        navigating = true;
        stroke.clear();
      } else {
        navigating = false;
        stroke = [_pixel(e.localPosition)];
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
        if (stroke.isEmpty || (stroke.last - p).distance >= .15) stroke.add(p);
      }
    });
  }

  void up(PointerEvent e, {bool cancel = false}) {
    if (!pointers.containsKey(e.pointer)) return;
    final points = List<Offset>.of(stroke);
    final commit =
        !cancel && !navigating && pointers.length == 1 && points.isNotEmpty;
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
    } else {
      widget.onStroke(widget.tool, points);
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
  );
  final Editor editor;
  final Offset origin;
  final double scale;
  final bool grid, onion;
  final List<Offset> points;
  final String tool;
  final int color, brush;
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
    if (image != null) {
      canvas.drawImage(
        image,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    if (points.isNotEmpty && tool != 'pan' && tool != 'eyedropper') {
      final p = Paint()
        ..color = tool == 'eraser' ? const Color(0x99ffffff) : Color(color)
        ..isAntiAlias = false;
      void dot(Offset v) => canvas.drawRect(
        Rect.fromLTWH(
          v.dx.floorToDouble() - (brush ~/ 2),
          v.dy.floorToDouble() - (brush ~/ 2),
          brush.toDouble(),
          brush.toDouble(),
        ),
        p,
      );
      if (tool == 'rectangle' || tool == 'ellipse') {
        final rect = Rect.fromPoints(
          Offset(
            points.first.dx.floorToDouble() + .5,
            points.first.dy.floorToDouble() + .5,
          ),
          Offset(
            points.last.dx.floorToDouble() + .5,
            points.last.dy.floorToDouble() + .5,
          ),
        );
        p.style = PaintingStyle.stroke;
        p.strokeWidth = brush.toDouble();
        if (tool == 'rectangle') {
          canvas.drawRect(rect, p);
        } else {
          canvas.drawOval(rect, p);
        }
      } else {
        final drawPoints = tool == 'line'
            ? [points.first, points.last]
            : points;
        dot(drawPoints.first);
        for (var n = 1; n < drawPoints.length; n++) {
          final a = drawPoints[n - 1], b = drawPoints[n];
          final count = math
              .max((b.dx - a.dx).abs(), (b.dy - a.dy).abs())
              .ceil();
          for (var i = 0; i <= count; i++) {
            dot(Offset.lerp(a, b, count == 0 ? 0 : i / count)!);
          }
        }
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

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}
