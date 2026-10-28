import 'package:flutter/painting.dart';

/// Tiled repeats edit one wrapped canvas; slide neighbors are read-only.
enum CanvasViewMode { normal, tiled, slide }

/// Offsets are in frame units. Tiled is deliberately bounded to nine cells,
/// avoiding unbounded paint work for one-pixel documents at low zoom.
List<Offset> canvasContextOffsets(CanvasViewMode mode) => switch (mode) {
  CanvasViewMode.normal => const [],
  CanvasViewMode.slide => const [Offset(-1, 0), Offset(1, 0)],
  CanvasViewMode.tiled => const [
    Offset(-1, -1),
    Offset(0, -1),
    Offset(1, -1),
    Offset(-1, 0),
    Offset(1, 0),
    Offset(-1, 1),
    Offset(0, 1),
    Offset(1, 1),
  ],
};

bool isEditableCanvasPoint(Offset point, int width, int height) =>
    point.dx >= 0 && point.dy >= 0 && point.dx < width && point.dy < height;

/// The finite repeated area accepts input in world coordinates. Keep those
/// coordinates continuous until rasterization; wrapping pointer endpoints first
/// would turn a short seam crossing into a line through the entire original.
bool isTiledCanvasPoint(Offset point, int width, int height) =>
    point.dx >= -width && point.dy >= -height &&
    point.dx < width * 2 && point.dy < height * 2;

Offset clampTiledCanvasPoint(Offset point, int width, int height) => Offset(
  point.dx.clamp(-width.toDouble(), width * 2 - .000001).toDouble(),
  point.dy.clamp(-height.toDouble(), height * 2 - .000001).toDouble(),
);
