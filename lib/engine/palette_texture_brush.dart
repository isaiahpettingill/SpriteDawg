import 'dart:math' as math;

import 'symmetry.dart';

const paletteTextureTools = {
  'metal',
  'cluster',
  'stripes',
  'sphere',
  'knife',
  'bark',
  'leaves',
  'ditherPaint',
  'ditherRetouch',
};

/// Oklab conversion from Björn Ottosson's public-domain reference matrices.
/// https://bottosson.github.io/posts/oklab/ (2021-01-25 matrices).
class PaletteLab {
  PaletteLab(int argb) {
    double linear(int shift) {
      final c = ((argb >> shift) & 255) / 255.0;
      return c <= .04045
          ? c / 12.92
          : math.pow((c + .055) / 1.055, 2.4).toDouble();
    }

    final r = linear(16), g = linear(8), b = linear(0);
    final x = math
        .pow(.4122214708 * r + .5363325363 * g + .0514459929 * b, 1 / 3)
        .toDouble();
    final y = math
        .pow(.2119034982 * r + .6806995451 * g + .1073969566 * b, 1 / 3)
        .toDouble();
    final z = math
        .pow(.0883024619 * r + .2817188376 * g + .6299787005 * b, 1 / 3)
        .toDouble();
    l = .2104542553 * x + .7936177850 * y - .0040720468 * z;
    a = 1.9779984951 * x - 2.4285922050 * y + .4505937099 * z;
    this.b = .0259040371 * x + .7827717662 * y - .8086757660 * z;
    alpha = ((argb >> 24) & 255) / 255.0;
  }
  late final double l, a, b, alpha;
}

/// Five actual palette indices, dark to light. No synthesized paint colors.
/// Prefer the selected index (including duplicates), then seek lightness steps
/// within a similar hue/chroma family and alpha band. Missing shades reuse the
/// nearest existing shade, rather than pulling an unrelated saturated hue.
List<int> paletteShadeRamp(
  List<int> palette,
  int color, {
  int? selectedIndex,
  int? transparentIndex,
}) {
  if (palette.isEmpty ||
      selectedIndex != null && selectedIndex == transparentIndex) {
    return [];
  }
  final labs = palette.map(PaletteLab.new).toList();
  final chosen = PaletteLab(color);
  final usable = [
    for (var i = 0; i < palette.length; i++)
      if (i != transparentIndex && labs[i].alpha > 0) i,
  ];
  if (usable.isEmpty || chosen.alpha == 0) return [];
  double sq(double x) => x * x;
  double distance(PaletteLab p, PaletteLab q) =>
      sq(p.l - q.l) +
      sq(p.a - q.a) +
      sq(p.b - q.b) +
      .5 * sq(p.alpha - q.alpha);
  var anchor = usable.first;
  for (final i in usable) {
    if (distance(labs[i], chosen) < distance(labs[anchor], chosen)) anchor = i;
  }
  if (selectedIndex != null && usable.contains(selectedIndex)) {
    anchor = selectedIndex;
  }
  final base = labs[anchor];
  final candidates = usable.where((i) {
    final p = labs[i];
    final chromaDistance = math.sqrt(sq(p.a - base.a) + sq(p.b - base.b));
    return (p.alpha - base.alpha).abs() <= .08 && chromaDistance <= .16;
  }).toList();
  final result = <int>[];
  for (final offset in [-.24, -.12, 0.0, .12, .24]) {
    var best = anchor, bestScore = double.infinity;
    for (final i in candidates) {
      final p = labs[i];
      if (offset < 0 && p.l > base.l + .000001 ||
          offset > 0 && p.l < base.l - .000001) {
        continue;
      }
      final score =
          sq(p.l - (base.l + offset).clamp(0.0, 1.0)) +
          2.0 * (sq(p.a - base.a) + sq(p.b - base.b)) +
          .5 * sq(p.alpha - base.alpha);
      if (score < bestScore - 1e-12 ||
          (score - bestScore).abs() <= 1e-12 && i == anchor) {
        best = i;
        bestScore = score;
      }
    }
    result.add(offset == 0 ? anchor : best);
  }
  return result;
}

/// Rasterizes into final palette indices. Last geometric stamp owns a pixel,
/// then callers blend exactly once against the pre-stroke image. Integer-point
/// resampling and collinear simplification remove pointer-event-rate effects.
Map<int, int> paletteTexturePixels({
  required String tool,
  required List<(int, int)> points,
  required int width,
  required int height,
  required int size,
  required List<int> ramp,
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
  if (points.isEmpty || ramp.isEmpty) return out;
  final p = <(int, int)>[];
  for (final point in points) {
    if (p.isNotEmpty && p.last == point) continue;
    while (p.length >= 2) {
      final a = p[p.length - 2], b = p.last;
      final dx = b.$1 - a.$1,
          dy = b.$2 - a.$2,
          ex = point.$1 - b.$1,
          ey = point.$2 - b.$2;
      if (dx * ey - dy * ex != 0 || dx * ex + dy * ey <= 0) break;
      p.removeLast();
    }
    p.add(point);
  }
  int hash(int x, int y) {
    var v =
        (x * 374761393 + y * 668265263 + (seed & 0xffffffff) * 69069) &
        0xffffffff;
    v = ((v ^ (v >> 13)) * 1274126177) & 0xffffffff;
    return (v ^ (v >> 16)) & 0x7fffffff;
  }

  int cluster(double x, double y, double cell) {
    final gx = (x / cell).floor(), gy = (y / cell).floor();
    var best = double.infinity, shade = 2;
    for (var cy = gy - 1; cy <= gy + 1; cy++) {
      for (var cx = gx - 1; cx <= gx + 1; cx++) {
        final h = hash(cx, cy);
        final px = (cx + .2 + (h % 601) / 1000) * cell,
            py = (cy + .2 + ((h >> 10) % 601) / 1000) * cell;
        final d = (x - px) * (x - px) + (y - py) * (y - py);
        if (d < best) {
          best = d;
          shade = (h >> 20) % 5;
        }
      }
    }
    return shade;
  }

  // Canvas-anchored grain: the seed changes the tree, not each dab. A fixed
  // vertical axis keeps bends, revisits and live-preview extensions seamless.
  // All distances are in ridge widths, so detail scales with the brush size.
  int bark(int x, int y) {
    final cell = math.max(2.0, size / 5);
    var u = x / cell;
    final v = y / cell;
    final knotColumn = (u / 6).floor(), knotRow = (v / 18).floor();
    for (var ky = knotRow - 1; ky <= knotRow + 1; ky++) {
      for (var kx = knotColumn - 1; kx <= knotColumn + 1; kx++) {
        final h = hash(kx + 1709, ky - 313);
        if (h % 3 != 0) continue;
        final cx = kx * 6 + 1.5 + ((h >> 3) % 301) / 100;
        final cy = ky * 18 + 4 + ((h >> 12) % 1001) / 100;
        final dx = u - cx, dy = (v - cy) / 2.8;
        final radius = math.sqrt(dx * dx + dy * dy);
        if (radius < .24) return 0;
        if (radius < .43) return 1;
        if (radius < .62) return 3;
        if (radius < .77) return 0;
        if (radius < .95) return dx < 0 ? 3 : 2;
        // Bend nearby grain around the elongated knot instead of stamping
        // disconnected concentric circles over otherwise straight stripes.
        if (radius < 2.2) {
          u += (dx < 0 ? -1 : 1) * (2.2 - radius) * .38;
        }
      }
    }
    final lane = u.floor(), segment = (v / 7).floor();
    final t = v / 7 - segment, smooth = t * t * (3 - 2 * t);
    var distance = double.infinity, side = 0.0, nearest = lane;
    for (var i = lane - 2; i <= lane + 2; i++) {
      final start = (hash(i, segment) % 1001) / 1000;
      final end = (hash(i, segment + 1) % 1001) / 1000;
      final center = i + .15 + .7 * (start + (end - start) * smooth);
      final delta = u - center;
      if (delta.abs() < distance) {
        distance = delta.abs();
        side = delta;
        nearest = i;
      }
    }
    // Uneven fissures, shadowed walls and narrow lit ridges. Short cracks
    // are coherent segments, never independent random bright pixels.
    if (distance < .10) return 0;
    if (distance < .23) return 1;
    if (side > 0 && distance < .34) return 4;
    if (side > 0 && distance < .49) return 3;
    final crack = v / 3 + (hash(nearest, 911) % 100) / 100;
    if (crack - crack.floor() < .09 && hash(nearest, crack.floor()) % 4 == 0) {
      return 1;
    }
    return 2;
  }

  // A canvas-anchored canopy of overlapping pointed leaves. Jitter, length,
  // orientation and layer order belong to a leaf, never to a stamp/pixel. The
  // almond contour has a dark interior/vein and coherent light-facing rims.
  int leaves(int x, int y) {
    final cell = math.max(3.0, size / 4);
    final u = x / cell, v = y / cell;
    final gx = u.floor(), gy = v.floor();
    var top = -1, shade = 0;
    for (var cy = gy - 2; cy <= gy + 2; cy++) {
      for (var cx = gx - 2; cx <= gx + 2; cx++) {
        final h = hash(cx + 381, cy - 719);
        final dx = u - (cx + .15 + (h % 701) / 1000);
        final dy = v - (cy + .15 + ((h >> 10) % 701) / 1000);
        final direction = (h >> 20) & 3;
        final along = switch (direction) {
          0 => dx,
          1 => (dx + dy) * .7071067811865476,
          2 => dy,
          _ => (dx - dy) * .7071067811865476,
        };
        final across = switch (direction) {
          0 => dy,
          1 => (dy - dx) * .7071067811865476,
          2 => -dx,
          _ => (dx + dy) * .7071067811865476,
        };
        final length = .68 + ((h >> 5) % 401) / 1000;
        final halfWidth = .30 + ((h >> 15) % 161) / 1000;
        final a = along / length, b = across / halfWidth;
        final contour = a.abs() + b * b;
        if (contour > 1 || h <= top) continue;
        top = h;
        // Backlit rims frame each leaf instead of reducing foliage to noise.
        if (contour > .62) {
          shade = dy < 0 || dx < -.15 ? 4 : 3;
        } else if (b.abs() < .15 || a < -.45) {
          shade = 1;
        } else {
          shade = 2;
        }
      }
    }
    return shade;
  }

  final leavesCache = <int, int>{};
  void emit(int x, int y, int shade) {
    for (final (xx, yy) in symmetry.points(x, y)) {
      // Leaves are a canvas-anchored field. Sample the destination's canonical
      // point so overlapping reflected dabs remain stable, even when a mixed-
      // parity rectangle needs nearest-pixel rounding.
      final value = tool == 'leaves'
          ? leavesCache.putIfAbsent(yy * width + xx, () {
              final sample = symmetry.canonicalPoint(xx, yy);
              return leaves(sample.$1, sample.$2);
            })
          : shade;
      out[yy * width + xx] = ramp[value.clamp(0, 4)];
    }
  }

  final clusterCache = <(int, int), int>{};
  final barkCache = <(int, int), int>{};
  void stamp(int x, int y, double tx, double ty) {
    final left = x - size ~/ 2, top = y - size ~/ 2;
    final bounds = symmetry.sourceBounds;
    if (left > bounds.$3 ||
        top > bounds.$4 ||
        left + size <= bounds.$1 ||
        top + size <= bounds.$2) {
      return;
    }
    final cell = math.max(2.0, size / 3);
    for (var oy = 0; oy < size; oy++) {
      for (var ox = 0; ox < size; ox++) {
        final nx = (2 * ox - size + 1) / size, ny = (2 * oy - size + 1) / size;
        final radius = nx * nx + ny * ny;
        if (radius > 1) continue;
        final px = x - size ~/ 2 + ox, py = y - size ~/ 2 + oy;
        if (px < bounds.$1 ||
            py < bounds.$2 ||
            px > bounds.$3 ||
            py > bounds.$4) {
          continue;
        }
        var shade = 2;
        if (tool == 'ditherPaint' || tool == 'ditherRetouch') {
          shade = 2;
        } else if (tool == 'cluster') {
          shade = clusterCache.putIfAbsent((
            px,
            py,
          ), () => cluster(px.toDouble(), py.toDouble(), cell));
        } else if (tool == 'bark') {
          shade = barkCache.putIfAbsent((px, py), () => bark(px, py));
        } else if (tool == 'leaves') {
          // Destination-anchored canonical sampling happens in emit.
          shade = 2;
        } else if (tool == 'stripes') {
          shade = cluster((px * tx + py * ty) / 4, -px * ty + py * tx, cell);
        } else if (tool == 'sphere') {
          final light =
              (.62 * math.sqrt(math.max(0, 1 - radius)) - .70 * ny - .18 * nx)
                  .clamp(-1.0, 1.0);
          shade = ((light + 1) * 2).round();
        } else {
          final normal = -nx * ty + ny * tx;
          if (tool == 'knife') {
            shade = normal < -.45
                ? 4
                : normal < 0
                ? 3
                : normal < .5
                ? 1
                : 0;
          } else {
            shade = normal < -.65
                ? 1
                : normal < -.25
                ? 3
                : normal < -.05
                ? 4
                : normal < .3
                ? 0
                : normal < .65
                ? 2
                : 1;
          }
        }
        emit(px, py, shade);
      }
    }
  }

  if (p.length == 1) {
    stamp(p.first.$1, p.first.$2, 1, 0);
    return out;
  }
  for (var j = 1; j < p.length; j++) {
    final from = p[j - 1], to = p[j];
    final vx = to.$1 - from.$1,
        vy = to.$2 - from.$2,
        length = math.sqrt((vx * vx + vy * vy).toDouble());
    final tx = vx / length, ty = vy / length;
    var x = from.$1, y = from.$2, e = vx.abs() - vy.abs();
    final dx = vx.abs(),
        dy = -vy.abs(),
        sx = vx > 0 ? 1 : -1,
        sy = vy > 0 ? 1 : -1;
    while (true) {
      stamp(x, y, tx, ty);
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
  return out;
}

/// Ordered dithering along the Oklab+alpha segment from pre-stroke background
/// to foreground. Picks real palette entries, never error-diffuses across dabs.
int ditherPaletteIndex(
  List<int> palette,
  int background,
  int foreground,
  int x,
  int y,
  int strength, {
  int? transparentIndex,
}) {
  if (palette.isEmpty) return 0;
  final bg = PaletteLab(
    background >> 24 == 0 ? foreground & 0xffffff : background,
  );
  final fg = PaletteLab(foreground);
  final delta = [
    fg.l - bg.l,
    fg.a - bg.a,
    fg.b - bg.b,
    (fg.alpha - bg.alpha) * .7,
  ];
  final length = delta.fold<double>(0, (v, c) => v + c * c);
  final amount = strength.clamp(0, 100) / 100;
  double distance(PaletteLab p) {
    final values = [
      p.l - bg.l - delta[0] * amount,
      p.a - bg.a - delta[1] * amount,
      p.b - bg.b - delta[2] * amount,
      (p.alpha - bg.alpha) * .7 - delta[3] * amount,
    ];
    return values.fold<double>(0, (v, c) => v + c * c);
  }

  var nearest = 0, nearestDistance = double.infinity;
  final candidates = <(int, double)>[];
  for (var i = 0; i < palette.length; i++) {
    final p = PaletteLab(i == transparentIndex ? 0 : palette[i]);
    final d = distance(p);
    if (d < nearestDistance) {
      nearest = i;
      nearestDistance = d;
    }
    if (length < 1e-12) continue;
    final values = [
      p.l - bg.l,
      p.a - bg.a,
      p.b - bg.b,
      (p.alpha - bg.alpha) * .7,
    ];
    var dot = 0.0;
    for (var j = 0; j < 4; j++) {
      dot += values[j] * delta[j];
    }
    final t = dot / length;
    var perpendicular = 0.0;
    for (var j = 0; j < 4; j++) {
      final e = values[j] - delta[j] * t;
      perpendicular += e * e;
    }
    if (t >= -.02 && t <= 1.02 && perpendicular <= .012) {
      candidates.add((i, t.clamp(0.0, 1.0)));
    }
  }
  if (candidates.isEmpty || length < 1e-12) return nearest;
  candidates.sort(
    (a, b) => a.$2 == b.$2 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  var lower = candidates.first, upper = candidates.last;
  for (final c in candidates) {
    if (c.$2 <= amount) lower = c;
    if (c.$2 >= amount) {
      upper = c;
      break;
    }
  }
  if (amount <= candidates.first.$2) return candidates.first.$1;
  if (amount >= candidates.last.$2) return candidates.last.$1;
  if ((upper.$2 - lower.$2).abs() < 1e-12) return nearest;
  const bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  final fraction = (amount - lower.$2) / (upper.$2 - lower.$2);
  return fraction > (bayer[(y & 3) * 4 + (x & 3)] + .5) / 16
      ? upper.$1
      : lower.$1;
}

/// Retouch preserves alpha exactly. If the palette cannot represent the source
/// alpha, leave that pixel unchanged rather than silently flattening it.
int retouchPaletteIndex(
  List<int> palette,
  int source,
  int x,
  int y, {
  int? transparentIndex,
}) {
  final alpha = (source >> 24) & 255;
  if (alpha == 0) return -1;
  final target = PaletteLab(source);
  double sq(double x) => x * x;
  double dist(PaletteLab p) =>
      sq(p.l - target.l) + sq(p.a - target.a) + sq(p.b - target.b);
  final candidates = <(int, PaletteLab)>[];
  for (var i = 0; i < palette.length; i++) {
    if (i == transparentIndex || (palette[i] >> 24) & 255 != alpha) continue;
    if (palette[i] == source) return i;
    candidates.add((i, PaletteLab(palette[i])));
  }
  if (candidates.isEmpty) return -1;
  candidates.sort((a, b) {
    final d = dist(a.$2).compareTo(dist(b.$2));
    return d == 0 ? a.$1.compareTo(b.$1) : d;
  });
  final near = candidates.take(8).toList();
  var low = near.first.$1, high = low, mix = 0.0, error = dist(near.first.$2);
  for (var i = 0; i < near.length; i++) {
    for (var j = i + 1; j < near.length; j++) {
      final a = near[i].$2, b = near[j].$2;
      final dl = b.l - a.l,
          da = b.a - a.a,
          db = b.b - a.b,
          len = dl * dl + da * da + db * db;
      if (len < 1e-12) continue;
      final t =
          (((target.l - a.l) * dl +
                      (target.a - a.a) * da +
                      (target.b - a.b) * db) /
                  len)
              .clamp(0.0, 1.0);
      // Penalize very distant endpoints so smooth tones do not turn into harsh
      // unrelated checkerboards merely because their average happens to match.
      final e =
          sq(a.l + dl * t - target.l) +
          sq(a.a + da * t - target.a) +
          sq(a.b + db * t - target.b) +
          .02 * len * t * (1 - t);
      if (e < error - 1e-12) {
        error = e;
        low = near[i].$1;
        high = near[j].$1;
        mix = t;
      }
    }
  }
  const bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  return mix > (bayer[(y & 3) * 4 + (x & 3)] + .5) / 16 ? high : low;
}
