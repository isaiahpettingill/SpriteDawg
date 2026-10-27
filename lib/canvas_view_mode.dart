import 'package:flutter/painting.dart';

/// Read-only context around the one editable central canvas.
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
