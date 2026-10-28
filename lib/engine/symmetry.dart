/// An exact orthogonal transform about the canvas center. Coordinates remain
/// doubled integers until the final rasterization, so compositions never drift.
class MirrorTransform {
  const MirrorTransform(this.xx, this.xy, this.yx, this.yy);

  final int xx, xy, yx, yy;

  MirrorTransform after(MirrorTransform other) => MirrorTransform(
    xx * other.xx + xy * other.yx,
    xx * other.xy + xy * other.yy,
    yx * other.xx + yy * other.yx,
    yx * other.xy + yy * other.yy,
  );

  (int, int) vector(int x, int y) => (xx * x + xy * y, yx * x + yy * y);

  (int, int) point(int width, int height, int x, int y) {
    final (u, v) = vector(2 * x - width + 1, 2 * y - height + 1);
    // Rectangles with differing width/height parity reflect pixel centers onto
    // half-pixels. Choose the nearest pixel, ties toward top/left, not a stretch.
    int half(int n) => n >= 0 ? n ~/ 2 : -((-n + 1) ~/ 2);
    return (half(u + width - 1), half(v + height - 1));
  }

  @override
  bool operator ==(Object other) =>
      other is MirrorTransform &&
      xx == other.xx &&
      xy == other.xy &&
      yx == other.yx &&
      yy == other.yy;

  @override
  int get hashCode => Object.hash(xx, xy, yx, yy);
}

/// The finite closure of the enabled center-line reflections (at most eight).
/// Transform before clipping: a rectangular canvas never stretches its copies.
class CanvasSymmetry {
  CanvasSymmetry({
    required this.width,
    required this.height,
    bool mirrorX = false,
    bool mirrorY = false,
    bool mirrorDiagonal = false,
    bool mirrorAntiDiagonal = false,
  }) {
    final generators = [
      if (mirrorX) const MirrorTransform(-1, 0, 0, 1),
      if (mirrorY) const MirrorTransform(1, 0, 0, -1),
      if (mirrorDiagonal) const MirrorTransform(0, 1, 1, 0),
      if (mirrorAntiDiagonal) const MirrorTransform(0, -1, -1, 0),
    ];
    for (var i = 0; i < transforms.length; i++) {
      for (final generator in generators) {
        final next = generator.after(transforms[i]);
        if (!transforms.contains(next)) transforms.add(next);
      }
    }
  }

  final int width, height;
  final List<MirrorTransform> transforms = [const MirrorTransform(1, 0, 0, 1)];

  /// Inclusive source window containing every pixel that can reflect into the
  /// canvas. Bounds come from exact integer affine maps, including half-pixel
  /// ties, not from pointer coordinates; extreme drags cannot allocate 16k².
  late final (int, int, int, int) sourceBounds = _sourceBounds();

  (int, int, int, int) _sourceBounds() {
    var left = 0, top = 0, right = width - 1, bottom = height - 1;
    (int, int) interval(int sign, int offset, int size) =>
        sign > 0 ? (-offset, size - 1 - offset) : (offset - size + 1, offset);
    for (final transform in transforms) {
      final (ox, oy) = transform.point(width, height, 0, 0);
      final xs = transform.xx != 0
          ? interval(transform.xx, ox, width)
          : interval(transform.yx, oy, height);
      final ys = transform.xy != 0
          ? interval(transform.xy, ox, width)
          : interval(transform.yy, oy, height);
      if (xs.$1 < left) left = xs.$1;
      if (xs.$2 > right) right = xs.$2;
      if (ys.$1 < top) top = ys.$1;
      if (ys.$2 > bottom) bottom = ys.$2;
    }
    return (left, top, right, bottom);
  }

  Iterable<(int, int)> points(int x, int y) sync* {
    final seen = <(int, int)>{};
    for (final transform in transforms) {
      final point = transform.point(width, height, x, y);
      if (point.$1 >= 0 &&
          point.$2 >= 0 &&
          point.$1 < width &&
          point.$2 < height &&
          seen.add(point)) {
        yield point;
      }
    }
  }

  /// Stable texture sampling representative; clipping does not change the field.
  (int, int) canonicalPoint(int x, int y) {
    var best = (x, y);
    for (final transform in transforms) {
      final p = transform.point(width, height, x, y);
      if (p.$1 < best.$1 || p.$1 == best.$1 && p.$2 < best.$2) best = p;
    }
    return best;
  }
}
