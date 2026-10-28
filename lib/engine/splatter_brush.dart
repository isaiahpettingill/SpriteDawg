import 'dart:math' as math;

import 'symmetry.dart';

/// A seeded burst of round droplets, resampled by travelled pixel distance.
/// Holding still never sprays more ink. Coverage is the strongest droplet at a
/// pixel, so overlapping dabs and symmetry blend once, not repeatedly darker.
/// Integer geometry and bounded LCG arithmetic are shared with the native port.
Map<int, int> splatterPixels({
  required List<(int, int)> points,
  required int width,
  required int height,
  required int size,
  int seed = 1,
  bool mirrorX = false,
  bool mirrorY = false,
  bool mirrorDiagonal = false,
  bool mirrorAntiDiagonal = false,
}) {
  final out = <int, int>{};
  final symmetry = CanvasSymmetry(
    width: width,
    height: height,
    mirrorX: mirrorX,
    mirrorY: mirrorY,
    mirrorDiagonal: mirrorDiagonal,
    mirrorAntiDiagonal: mirrorAntiDiagonal,
  );
  if (points.isEmpty) return out;
  final path = <(int, int)>[];
  for (final point in points) {
    if (path.isNotEmpty && path.last == point) continue;
    while (path.length >= 2) {
      final a = path[path.length - 2], b = path.last;
      final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
      final ex = point.$1 - b.$1, ey = point.$2 - b.$2;
      if (dx * ey != dy * ex || dx * ex + dy * ey <= 0) break;
      path.removeLast();
    }
    path.add(point);
  }
  void emit(int x, int y, int coverage) {
    for (final (xx, yy) in symmetry.points(x, y)) {
      final key = yy * width + xx;
      out[key] = math.max(out[key] ?? 0, coverage);
    }
  }

  final stamped = <(int, int)>{};
  void stamp(int x, int y) {
    if (!stamped.add((x, y))) return;
    final left = x - size ~/ 2, top = y - size ~/ 2;
    final bounds = symmetry.sourceBounds;
    if (left > bounds.$3 || top > bounds.$4 ||
        left + size <= bounds.$1 || top + size <= bounds.$2) {
      return;
    }
    var state =
        (x * 374761393 + y * 668265263 + (seed & 0xffffffff) * 69069) &
        0xffffffff;
    int random() {
      state = (state * 1664525 + 1013904223) & 0xffffffff;
      return state >> 16;
    }

    final count = size == 1 ? 1 : 2 + size ~/ 3;
    final maxDiameter = math.max(1, size ~/ 5);
    for (var drop = 0; drop < count; drop++) {
      final cx = drop == 0 ? size ~/ 2 : random() % size;
      final cy = drop == 0 ? size ~/ 2 : random() % size;
      final diameter = 1 + random() % maxDiameter;
      final coverage = 64 + random() % 192;
      for (var oy = 0; oy < diameter; oy++) {
        for (var ox = 0; ox < diameter; ox++) {
          final dx = 2 * ox - diameter + 1, dy = 2 * oy - diameter + 1;
          if (dx * dx + dy * dy > diameter * diameter) continue;
          final px = cx - diameter ~/ 2 + ox;
          final py = cy - diameter ~/ 2 + oy;
          final bx = 2 * px - size + 1, by = 2 * py - size + 1;
          if (px < 0 ||
              py < 0 ||
              px >= size ||
              py >= size ||
              bx * bx + by * by > size * size) {
            continue;
          }
          emit(left + px, top + py, coverage);
        }
      }
    }
  }

  stamp(path.first.$1, path.first.$2);
  final spacing = math.max(1, size ~/ 2);
  var travelled = 0;
  for (var i = 1; i < path.length; i++) {
    final from = path[i - 1], to = path[i];
    var x = from.$1, y = from.$2;
    final dx = (to.$1 - x).abs(), dy = -(to.$2 - y).abs();
    final sx = x < to.$1 ? 1 : -1, sy = y < to.$2 ? 1 : -1;
    var error = dx + dy;
    while (x != to.$1 || y != to.$2) {
      final twice = error * 2;
      if (twice >= dy) {
        error += dy;
        x += sx;
      }
      if (twice <= dx) {
        error += dx;
        y += sy;
      }
      travelled++;
      if (travelled % spacing == 0) stamp(x, y);
    }
  }
  return out;
}
