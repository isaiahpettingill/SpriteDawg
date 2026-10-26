import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Pixel geometry used only for transient previews; the engines remain the
/// authoritative editors. Fill/blur/jumble intentionally show a cursor instead
/// of pretending a color stroke is their computed result.
Uint8List previewStrokeMask({
  required int width,
  required int height,
  required String tool,
  required List<Offset> points,
  required int size,
  bool filled = false,
  bool mirrorX = false,
  bool mirrorY = false,
  int seed = 1,
  int density = 12,
}) {
  final out = Uint8List(width * height);
  if (points.isEmpty) return out;
  var randomState = seed & 0xffffffff;
  int random() {
    randomState = (1664525 * randomState + 1013904223) & 0xffffffff;
    return randomState >> 16;
  }

  void pixel(int x, int y) {
    for (final xx in [x, if (mirrorX) width - 1 - x]) {
      for (final yy in [y, if (mirrorY) height - 1 - y]) {
        if (xx >= 0 && yy >= 0 && xx < width && yy < height) {
          out[yy * width + xx] = 1;
        }
      }
    }
  }

  void dot(int x, int y) {
    if (tool == 'spray') {
      for (var i = 0; i < density; i++) {
        final ox = random() % size,
            oy = random() % size,
            dx = 2 * ox - size + 1,
            dy = 2 * oy - size + 1;
        if (dx * dx + dy * dy <= size * size) {
          pixel(x - size ~/ 2 + ox, y - size ~/ 2 + oy);
        }
      }
    } else {
      for (var yy = y - size ~/ 2; yy < y - size ~/ 2 + size; yy++) {
        for (var xx = x - size ~/ 2; xx < x - size ~/ 2 + size; xx++) {
          pixel(xx, yy);
        }
      }
    }
  }

  void line((int, int) from, (int, int) to, {bool skipFirst = false}) {
    var x = from.$1,
        y = from.$2,
        e = (to.$1 - from.$1).abs() - (to.$2 - from.$2).abs();
    final dx = (to.$1 - x).abs(),
        dy = -(to.$2 - y).abs(),
        sx = x < to.$1 ? 1 : -1,
        sy = y < to.$2 ? 1 : -1;
    var first = true;
    while (true) {
      if (!skipFirst || !first) dot(x, y);
      first = false;
      if (x == to.$1 && y == to.$2) break;
      final twice = e * 2;
      if (twice >= dy) {
        e += dy;
        x += sx;
      }
      if (twice <= dx) {
        e += dx;
        y += sy;
      }
    }
  }

  final p = points.map((v) => (v.dx.floor(), v.dy.floor())).toList(),
      first = p.first,
      last = p.last;
  if ((tool == 'rectangle' || tool == 'ellipse') && filled) {
    final l = math.min(first.$1, last.$1),
        r = math.max(first.$1, last.$1),
        t = math.min(first.$2, last.$2),
        b = math.max(first.$2, last.$2),
        w = r - l + 1,
        h = b - t + 1;
    for (var y = math.max(0, t); y <= math.min(height - 1, b); y++) {
      for (var x = math.max(0, l); x <= math.min(width - 1, r); x++) {
        final dx = 2 * x - l - r, dy = 2 * y - t - b;
        if (tool == 'rectangle' ||
            dx * dx * h * h + dy * dy * w * w <= w * w * h * h) {
          pixel(x, y);
        }
      }
    }
  } else if (tool == 'rectangle') {
    final b = (last.$1, first.$2), e = (first.$1, last.$2);
    line(first, b);
    line(b, last);
    line(last, e);
    line(e, first);
  } else if (tool == 'ellipse') {
    final rx = (last.$1 - first.$1).abs() / 2,
        ry = (last.$2 - first.$2).abs() / 2,
        cx = (first.$1 + last.$1) / 2,
        cy = (first.$2 + last.$2) / 2,
        steps = math.max(12, (2 * math.pi * math.max(rx, ry)).ceil());
    var previous = ((cx + rx).round(), cy.round());
    for (var i = 1; i <= steps; i++) {
      final a = 2 * math.pi * i / steps,
          next = (
            (cx + rx * math.cos(a)).round(),
            (cy + ry * math.sin(a)).round(),
          );
      line(previous, next);
      previous = next;
    }
  } else if (tool == 'line') {
    line(first, last);
  } else {
    dot(first.$1, first.$2);
    for (var i = 1; i < p.length; i++) {
      if (tool == 'spray' && p[i - 1] == p[i]) {
        dot(p[i].$1, p[i].$2);
      } else {
        line(p[i - 1], p[i], skipFirst: true);
      }
    }
  }
  return out;
}

/// Compact drawing runs for the viewport. A one-pixel stroke on a 2048² canvas
/// only allocates its tiny local footprint, not a full-canvas preview buffer.
List<Rect> previewStrokeRuns({
  required int width,
  required int height,
  required String tool,
  required List<Offset> points,
  required int size,
  bool filled = false,
  bool mirrorX = false,
  bool mirrorY = false,
  int seed = 1,
  int density = 12,
}) {
  if (points.isEmpty) return [];
  final relevant = const {'line', 'rectangle', 'ellipse'}.contains(tool)
      ? [points.first, points.last]
      : points;
  var minX = relevant.first.dx.floor(),
      maxX = minX,
      minY = relevant.first.dy.floor(),
      maxY = minY;
  for (final point in relevant) {
    minX = math.min(minX, point.dx.floor());
    maxX = math.max(maxX, point.dx.floor());
    minY = math.min(minY, point.dy.floor());
    maxY = math.max(maxY, point.dy.floor());
  }
  final margin = size ~/ 2 + 1;
  final left = math.max(0, minX - margin),
      top = math.max(0, minY - margin),
      right = math.min(width, maxX + margin + 1),
      bottom = math.min(height, maxY + margin + 1);
  if (right <= left || bottom <= top) return [];
  final w = right - left, h = bottom - top;
  final mask = previewStrokeMask(
    width: w,
    height: h,
    tool: tool,
    points: points
        .map((p) => p - Offset(left.toDouble(), top.toDouble()))
        .toList(),
    size: size,
    filled: filled,
    seed: seed,
    density: density,
  );
  final rows = <int, List<(int, int)>>{};
  void add(int y, int start, int end) {
    (rows[y] ??= []).add((start, end));
  }

  for (var y = 0; y < h; y++) {
    var x = 0;
    while (x < w) {
      if (mask[y * w + x] == 0) {
        x++;
        continue;
      }
      final start = x;
      while (x < w && mask[y * w + x] != 0) {
        x++;
      }
      final yy = y + top, a = start + left, b = x + left;
      add(yy, a, b);
      if (mirrorX) add(yy, width - b, width - a);
      if (mirrorY) add(height - 1 - yy, a, b);
      if (mirrorX && mirrorY) add(height - 1 - yy, width - b, width - a);
    }
  }
  final output = <Rect>[];
  for (final entry in rows.entries) {
    final spans = entry.value..sort((a, b) => a.$1.compareTo(b.$1));
    var start = spans.first.$1, end = spans.first.$2;
    for (final span in spans.skip(1)) {
      if (span.$1 <= end) {
        end = math.max(end, span.$2);
      } else {
        output.add(
          Rect.fromLTWH(
            start.toDouble(),
            entry.key.toDouble(),
            (end - start).toDouble(),
            1,
          ),
        );
        start = span.$1;
        end = span.$2;
      }
    }
    output.add(
      Rect.fromLTWH(
        start.toDouble(),
        entry.key.toDouble(),
        (end - start).toDouble(),
        1,
      ),
    );
  }
  return output;
}
