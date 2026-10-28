import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'engine/symmetry.dart';

/// Pixel geometry used only for transient previews; the engines remain the
/// authoritative editors. Fill/blur/jumble intentionally show a cursor instead
/// of pretending a color stroke is their computed result. [originX]/[originY]
/// locate a bounded output window without changing source-coordinate rounding.
Uint8List previewStrokeMask({
  required int width,
  required int height,
  required String tool,
  required List<Offset> points,
  required int size,
  bool filled = false,
  bool wrap = false,
  bool mirrorX = false,
  bool mirrorY = false,
  bool mirrorDiagonal = false,
  bool mirrorAntiDiagonal = false,
  int originX = 0,
  int originY = 0,
  Set<int>? touchedRows,
  int seed = 1,
  int density = 12,
}) {
  final out = Uint8List(width * height);
  if (points.isEmpty) return out;
  if (wrap) {
    // Translate the whole path by its starting tile, not each point separately.
    // This preserves seam crossings and negative-half ellipse rounding parity.
    final start = points.first;
    final dx = start.dx.floor() - start.dx.floor() % width;
    final dy = start.dy.floor() - start.dy.floor() % height;
    points = points
        .map((p) => p - Offset(dx.toDouble(), dy.toDouble()))
        .toList();
  }
  var randomState = seed & 0xffffffff;
  int random() {
    randomState = (1664525 * randomState + 1013904223) & 0xffffffff;
    return randomState >> 16;
  }

  final symmetry = CanvasSymmetry(
    width: width,
    height: height,
    mirrorX: mirrorX,
    mirrorY: mirrorY,
    mirrorDiagonal: mirrorDiagonal,
    mirrorAntiDiagonal: mirrorAntiDiagonal,
    wrap: wrap,
  );
  void pixel(int x, int y) {
    for (final point in symmetry.points(x - originX, y - originY)) {
      out[point.$2 * width + point.$1] = 1;
      touchedRows?.add(point.$2);
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
    if (wrap) {
      for (var yy = 0; yy < height; yy++) {
        final y = periodicRepresentative(t, b, yy, height);
        if (y == null) continue;
        for (var xx = 0; xx < width; xx++) {
          final x = periodicRepresentative(l, r, xx, width);
          if (x == null) continue;
          final dx = 2 * x - l - r, dy = 2 * y - t - b;
          if (tool == 'rectangle' ||
              dx * dx * h * h + dy * dy * w * w <= w * w * h * h) {
            pixel(xx, yy);
          }
        }
      }
    } else {
      final bounds = symmetry.sourceBounds;
      for (
        var y = math.max(bounds.$2 + originY, t);
        y <= math.min(bounds.$4 + originY, b);
        y++
      ) {
        for (
          var x = math.max(bounds.$1 + originX, l);
          x <= math.min(bounds.$3 + originX, r);
          x++
        ) {
          final dx = 2 * x - l - r, dy = 2 * y - t - b;
          if (tool == 'rectangle' ||
              dx * dx * h * h + dy * dy * w * w <= w * w * h * h) {
            pixel(x, y);
          }
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
  bool wrap = false,
  bool mirrorX = false,
  bool mirrorY = false,
  bool mirrorDiagonal = false,
  bool mirrorAntiDiagonal = false,
  int seed = 1,
  int density = 12,
}) {
  if (points.isEmpty) return [];
  if (wrap) {
    // Tiled output is always bounded by one original canvas, not by the
    // world-space distance between pointer samples or the nine visible copies.
    final rows = <int>{};
    final mask = previewStrokeMask(
      touchedRows: rows,
      width: width,
      height: height,
      tool: tool,
      points: points,
      size: size,
      filled: filled,
      wrap: true,
      mirrorX: mirrorX,
      mirrorY: mirrorY,
      mirrorDiagonal: mirrorDiagonal,
      mirrorAntiDiagonal: mirrorAntiDiagonal,
      seed: seed,
      density: density,
    );
    final runs = <Rect>[];
    for (final y in rows) {
      var x = 0;
      while (x < width) {
        if (mask[y * width + x] == 0) {
          x++;
          continue;
        }
        final start = x;
        while (x < width && mask[y * width + x] != 0) {
          x++;
        }
        runs.add(
          Rect.fromLTWH(
            start.toDouble(),
            y.toDouble(),
            (x - start).toDouble(),
            1,
          ),
        );
      }
    }
    return runs;
  }
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
  final symmetry = CanvasSymmetry(
    width: width,
    height: height,
    mirrorX: mirrorX,
    mirrorY: mirrorY,
    mirrorDiagonal: mirrorDiagonal,
    mirrorAntiDiagonal: mirrorAntiDiagonal,
    wrap: wrap,
  );
  final margin = size ~/ 2 + 1, bounds = symmetry.sourceBounds;
  // Preserve off-canvas source pixels that reflect into a rectangular canvas,
  // but bound the allocation by the canvas, even for very distant pointers.
  final left = math.max(bounds.$1, minX - margin),
      top = math.max(bounds.$2, minY - margin),
      right = math.min(bounds.$3 + 1, maxX + margin + 1),
      bottom = math.min(bounds.$4 + 1, maxY + margin + 1);
  if (right <= left || bottom <= top) return [];
  final w = right - left, h = bottom - top;
  final mask = previewStrokeMask(
    width: w,
    height: h,
    tool: tool,
    // Rasterize in original coordinates. Translating first would change Dart's
    // away-from-zero rounding at negative half-pixels on ellipse outlines.
    points: points,
    originX: left,
    originY: top,
    size: size,
    filled: filled,
    seed: seed,
    density: density,
  );
  final rows = <int, List<(int, int)>>{};
  void add(int y, int start, int end) {
    start = math.max(0, start);
    end = math.min(width, end);
    if (y < 0 || y >= height || end <= start) return;
    // Merge as we go: rotated wide fills must not allocate one interval per
    // pixel merely to merge all of them at the end.
    final spans = rows[y] ??= [];
    var at = 0;
    while (at < spans.length && spans[at].$2 < start) {
      at++;
    }
    while (at < spans.length && spans[at].$1 <= end) {
      final span = spans.removeAt(at);
      start = math.min(start, span.$1);
      end = math.max(end, span.$2);
    }
    spans.insert(at, (start, end));
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
      for (final transform in symmetry.transforms) {
        final from = transform.point(width, height, a, yy);
        final to = transform.point(width, height, b - 1, yy);
        if (from.$2 == to.$2) {
          add(from.$2, math.min(from.$1, to.$1), math.max(from.$1, to.$1) + 1);
        } else {
          final top = math.max(0, math.min(from.$2, to.$2));
          final bottom = math.min(height - 1, math.max(from.$2, to.$2));
          for (var row = top; row <= bottom; row++) {
            add(row, from.$1, from.$1 + 1);
          }
        }
      }
    }
  }
  return [
    for (final row in rows.entries)
      for (final span in row.value)
        Rect.fromLTWH(
          span.$1.toDouble(),
          row.key.toDouble(),
          (span.$2 - span.$1).toDouble(),
          1,
        ),
  ];
}
