import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'aseprite.dart';
import 'document.dart';
import 'default_user_data.dart';
import 'palette_operations.dart';
import 'palette_texture_brush.dart';
import 'splatter_brush.dart';
import 'symmetry.dart';

/// Portable Linux editing backend with exactly the Android channel contract.
/// File picking, atomic recovery and PNG encoding belong to the platform adapter.
class EditorEngine {
  SpriteDocument document = SpriteDocument.create();
  int frame = 0, layer = 0;
  bool dirty = false, recoveryAvailable = false;
  final List<SpriteDocument> _undo = [], _redo = [];
  void Function(SpriteDocument)? validateCandidate;
  int historyBudgetBytes = 48 * 1024 * 1024;
  void replace(SpriteDocument d, {bool unsaved = false}) {
    validateCandidate?.call(d);
    document = d;
    frame = 0;
    layer = d.layers.lastIndexWhere((l) => l.visible && l.flags & 2 != 0);
    if (layer < 0) layer = 0;
    dirty = unsaved;
    _undo.clear();
    _redo.clear();
  }

  void load(Uint8List bytes, {bool unsaved = false}) =>
      replace(AsepriteCodec.decode(bytes), unsaved: unsaved);
  Uint8List encode() => AsepriteCodec.encode(document);
  void saved() => dirty = false;
  int _n(Map<String, dynamic> a, String key, int fallback) =>
      (a[key] as num?)?.toInt() ?? fallback;
  Map<String, dynamic> invoke(
    String method, [
    Map<String, dynamic> args = const {},
  ]) {
    switch (method) {
      case 'thumbnails':
        return thumbnails(args);
      case 'frameImage':
        return frameImage(args);
      case 'previewStroke':
        return previewStroke(args);
      case 'init':
      case 'state':
        break;
      case 'new':
        replace(
          newSprite(
            _n(args, 'width', 32),
            _n(args, 'height', 32),
            defaultUserData(args),
          ),
        );
        break;
      case 'select':
        final f = _n(args, 'frame', frame), l = _n(args, 'layer', layer);
        require(
          f >= 0 &&
              f < document.frames.length &&
              l >= 0 &&
              l < document.layers.length,
          'Invalid selection',
        );
        frame = f;
        layer = l;
        break;
      case 'stroke':
        stroke(args);
        break;
      case 'edit':
        edit(args);
        break;
      case 'undo':
        if (_undo.isNotEmpty) {
          validateCandidate?.call(_undo.last);
          _redo.add(document);
          document = _undo.removeLast();
          dirty = true;
          _clamp();
        }
        break;
      case 'redo':
        if (_redo.isNotEmpty) {
          validateCandidate?.call(_redo.last);
          _undo.add(document);
          document = _redo.removeLast();
          dirty = true;
          _clamp();
        }
        break;
      default:
        throw UnsupportedError('Platform adapter must handle $method');
    }
    return state();
  }

  /// Render a candidate stroke without touching document, undo or dirty state.
  /// stroke() already clones before mutation, so the temporary engine may share
  /// the immutable base until that point without a second deep copy.
  Map<String, dynamic> previewStroke(Map<String, dynamic> args) {
    final candidate = EditorEngine()
      ..document = document
      ..frame = frame
      ..layer = layer;
    candidate.stroke(args);
    return {
      'width': document.width,
      'height': document.height,
      'pixels': rgbaBytes(candidate.document.composite(frame)),
    };
  }

  /// Full-resolution read-only neighbor preview; never selects or edits a frame.
  Map<String, dynamic> frameImage(Map<String, dynamic> args) {
    final index = args['frame'];
    require(
      index is int && index >= 0 && index < document.frames.length,
      'Invalid preview frame',
    );
    return {
      'frame': index,
      'width': document.width,
      'height': document.height,
      'pixels': rgbaBytes(document.composite(index as int)),
    };
  }

  /// Bounded, read-only previews. Never changes the active frame or undo stack.
  Map<String, dynamic> thumbnails(Map<String, dynamic> args) {
    final requested = args['frames'];
    require(
      requested is List && requested.length <= 32,
      'Request at most 32 thumbnails',
    );
    final indices = (requested as List).map((value) {
      require(
        value is int && value >= 0 && value < document.frames.length,
        'Invalid thumbnail frame',
      );
      return value as int;
    }).toList();
    final requestedSize = args['maxSize'] ?? 48;
    require(
      requestedSize is int && requestedSize > 0,
      'Invalid thumbnail size',
    );
    final limit = (requestedSize as int).clamp(1, 64);
    final scale = math.min(
      1.0,
      limit / math.max(document.width, document.height),
    );
    final width = math.max(1, (document.width * scale).round());
    final height = math.max(1, (document.height * scale).round());
    return {
      'thumbnails': indices.map((index) {
        final pixels = Uint32List(width * height);
        for (var layer = 0; layer < document.layers.length; layer++) {
          final info = document.layers[layer];
          if (!info.visible) continue;
          final cel = document.resolved(index, layer);
          if (cel == null) continue;
          final opacity = (info.opacity * cel.opacity + 127) ~/ 255;
          for (var y = 0; y < height; y++) {
            for (var x = 0; x < width; x++) {
              final sx = x * document.width ~/ width - cel.x,
                  sy = y * document.height ~/ height - cel.y;
              if (sx >= 0 && sy >= 0 && sx < cel.width && sy < cel.height) {
                final i = y * width + x;
                pixels[i] = over(
                  pixels[i],
                  document.display(
                    cel.pixels[sy * cel.width + sx],
                    index,
                    layer,
                  ),
                  opacity,
                );
              }
            }
          }
        }
        return {
          'frame': index,
          'width': width,
          'height': height,
          'pixels': rgbaBytes(pixels),
        };
      }).toList(),
    };
  }

  void _clamp() {
    frame = frame.clamp(0, document.frames.length - 1);
    layer = layer.clamp(0, document.layers.length - 1);
  }

  /// Apply a validated document-level operation as one undoable transaction.
  void applyDocumentEdit(void Function(SpriteDocument) change) {
    _mutate(change);
    _clamp();
  }

  void _mutate(void Function(SpriteDocument) change) {
    final next = document.copy();
    change(next);
    validateCandidate?.call(next);
    _undo.add(document);
    _redo.clear();
    int userBytes(UserData? u) =>
        (u?.properties?.length ?? 0) + (u?.text?.length ?? 0) * 2;
    int bytes(SpriteDocument d) =>
        1024 +
        userBytes(d.data) +
        d.layers.fold<int>(
          0,
          (n, l) => n + l.name.length * 2 + userBytes(l.data),
        ) +
        d.tags.fold<int>(
          0,
          (n, t) => n + t.name.length * 2 + userBytes(t.data),
        ) +
        d.frames.fold<int>(
          0,
          (n, f) =>
              n +
              f.palette.length * 8 +
              f.metadata.fold<int>(0, (n, c) => n + c.bytes.length) +
              f.cels.fold<int>(
                0,
                (n, c) => n + (c?.pixels.length ?? 0) * 4 + userBytes(c?.data),
              ),
        );
    while (_undo.length > 30 ||
        (_undo.length > 1 &&
            _undo.fold<int>(0, (n, d) => n + bytes(d)) > historyBudgetBytes)) {
      _undo.removeAt(0);
    }
    document = next;
    dirty = true;
  }

  void stroke(Map<String, dynamic> a) {
    final tool = a['tool'] as String? ?? 'pencil';
    require(
      [
        'pencil',
        'eraser',
        'fill',
        'gradient',
        'line',
        'rectangle',
        'ellipse',
        'spray',
        'splatter',
        'airbrush',
        'blur',
        'jumble',
        ...paletteTextureTools,
      ].contains(tool),
      'Unknown tool',
    );
    final points = (a['points'] as List? ?? [])
        .map((p) => ((p[0] as num).toInt(), (p[1] as num).toInt()))
        .toList();
    if (points.isEmpty) return;
    require(
      points.length <= 100000 &&
          points.every((p) => p.$1.abs() <= 8192 && p.$2.abs() <= 8192),
      'Stroke exceeds safe limits',
    );
    // A tap has no direction and must not create an undo entry.
    if (tool == 'gradient' && points.first == points.last) return;
    final size = _n(
          a,
          'size',
          tool == 'spray' || tool == 'airbrush' || tool == 'splatter' ? 12 : 1,
        ).clamp(1, 32),
        color = _n(a, 'color', 0xff000000);
    final gradient = tool == 'fill' && a['gradient'] == true,
        direction = a['gradientDirection'] ?? 'vertical';
    if (gradient) {
      require(
        direction == 'horizontal' || direction == 'vertical',
        'Invalid gradient direction',
      );
    }
    final secondary = _n(a, 'secondaryColor', color),
        density = _n(a, 'density', 12).clamp(1, 100),
        strength = _n(a, 'strength', 50).clamp(1, 100);
    final mirrorX = a['mirrorX'] == true,
        mirrorY = a['mirrorY'] == true,
        mirrorDiagonal = a['mirrorDiagonal'] == true,
        mirrorAntiDiagonal = a['mirrorAntiDiagonal'] == true,
        paletteIndex = a['paletteIndex'];
    if ((document.depth == 8 || paletteTextureTools.contains(tool)) &&
        paletteIndex != null) {
      require(
        paletteIndex is int &&
            paletteIndex >= 0 &&
            paletteIndex < document.frames[frame].palette.length,
        'Invalid palette index',
      );
    }
    final symmetry = CanvasSymmetry(
      width: document.width,
      height: document.height,
      mirrorX: mirrorX,
      mirrorY: mirrorY,
      mirrorDiagonal: mirrorDiagonal,
      mirrorAntiDiagonal: mirrorAntiDiagonal,
    );
    var randomState = _n(a, 'seed', 1) & 0xffffffff;
    int random() {
      randomState = (1664525 * randomState + 1013904223) & 0xffffffff;
      return randomState >> 16;
    }

    require(document.layers[layer].visible, 'Show this layer before drawing');
    require(document.layers[layer].flags & 2 != 0, 'This layer is locked');
    require(
      tool != 'eraser' || document.layers[layer].flags & 8 == 0,
      'Convert background layer to transparent before erasing',
    );
    if (tool == 'splatter') {
      if (color >> 24 == 0) return;
      final d = document, source = document.resolved(frame, layer);
      final index = d.depth == 8
          ? paletteIndex as int? ?? d.drawingColor(color, frame)
          : null;
      if (index != null && d.display(index, frame, layer) >> 24 == 0) return;
      final pixels = splatterPixels(
        points: points,
        width: d.width,
        height: d.height,
        size: size,
        seed: _n(a, 'seed', 1),
        mirrorX: mirrorX,
        mirrorY: mirrorY,
        mirrorDiagonal: mirrorDiagonal,
        mirrorAntiDiagonal: mirrorAntiDiagonal,
      );
      final changes = <int, int>{};
      for (final entry in pixels.entries) {
        final x = entry.key % d.width, y = entry.key ~/ d.width;
        final sx = x - (source?.x ?? 0), sy = y - (source?.y ?? 0);
        final original =
            source != null &&
                sx >= 0 &&
                sy >= 0 &&
                sx < source.width &&
                sy < source.height
            ? source.pixels[sy * source.width + sx]
            : d.depth == 8
            ? d.transparentIndex
            : 0;
        // Indexed paint uses the exact selected entry, including its alpha.
        // Only RGB/grayscale paint varies opacity; never synthesize indices.
        final alpha = ((color >> 24) * entry.value + 127) ~/ 255;
        if (index == null && alpha == 0) continue;
        final ink = (color & 0xffffff) | (alpha << 24);
        final value = index ?? d.drawingColor(over(original, ink), frame);
        if (value != original) changes[entry.key] = value;
      }
      if (changes.isEmpty) return;
      _mutate((d) {
        final c = d.editable(frame, layer);
        for (final entry in changes.entries) {
          final x = entry.key % d.width, y = entry.key ~/ d.width;
          c.pixels[(y - c.y) * c.width + x - c.x] = entry.value;
        }
      });
      return;
    }
    if (paletteTextureTools.contains(tool)) {
      final palette = document.frames[frame].palette;
      final transparent =
          document.depth == 8 && document.layers[layer].flags & 8 == 0
          ? document.transparentIndex
          : null;
      final dither = tool == 'ditherPaint' || tool == 'ditherRetouch';
      final ramp = dither
          ? List<int>.filled(5, 0)
          : paletteShadeRamp(
              palette,
              color,
              selectedIndex: paletteIndex as int?,
              transparentIndex: transparent,
            );
      if (palette.isEmpty || ramp.isEmpty) return;
      final pixels = paletteTexturePixels(
        tool: tool,
        points: points,
        width: document.width,
        height: document.height,
        size: size,
        ramp: ramp,
        seed: _n(a, 'seed', 1),
        mirrorX: mirrorX,
        mirrorY: mirrorY,
        mirrorDiagonal: mirrorDiagonal,
        mirrorAntiDiagonal: mirrorAntiDiagonal,
      );
      if (pixels.isEmpty) return;
      final d = document, source = document.resolved(frame, layer);
      final changes = <int, int>{};
      final cache = <(int, int), int>{};
      for (final entry in pixels.entries) {
        final x = entry.key % d.width, y = entry.key ~/ d.width;
        final sx = x - (source?.x ?? 0), sy = y - (source?.y ?? 0);
        final originalValue =
            source != null &&
                sx >= 0 &&
                sy >= 0 &&
                sx < source.width &&
                sy < source.height
            ? source.pixels[sy * source.width + sx]
            : d.depth == 8
            ? d.transparentIndex
            : 0;
        final original = d.display(originalValue, frame, layer);
        var index = entry.value;
        if (dither) {
          index = cache.putIfAbsent(
            (original, (y & 3) * 4 + (x & 3)),
            () => tool == 'ditherRetouch'
                ? retouchPaletteIndex(
                    palette,
                    original,
                    x,
                    y,
                    transparentIndex: transparent,
                  )
                : ditherPaletteIndex(
                    palette,
                    original,
                    color,
                    x,
                    y,
                    strength,
                    transparentIndex: transparent,
                  ),
          );
          if (index < 0) continue;
        }
        final ink = index == transparent ? 0 : palette[index];
        if (tool == 'ditherRetouch' && ink == original) continue;
        final value = d.depth == 8
            ? index
            : d.drawingColor(dither ? ink : over(original, ink), frame);
        if (value != originalValue) changes[entry.key] = value;
      }
      if (changes.isEmpty) return;
      _mutate((d) {
        final c = d.editable(frame, layer);
        for (final entry in changes.entries) {
          final x = entry.key % d.width, y = entry.key ~/ d.width;
          c.pixels[(y - c.y) * c.width + x - c.x] = entry.value;
        }
      });
      return;
    }
    _mutate((d) {
      final c = d.editable(frame, layer),
          v =
              d.depth == 8 &&
                  paletteIndex != null &&
                  tool != 'eraser' &&
                  tool != 'gradient' &&
                  !gradient &&
                  tool != 'blur'
              ? paletteIndex as int
              : d.drawingColor(color, frame, erase: tool == 'eraser');
      final effect = tool == 'blur' || tool == 'jumble';
      final original = (effect || tool == 'fill')
          ? Uint32List.fromList(c.pixels)
          : c.pixels;
      final covered = <int>{}, painted = <int>{};
      final accumulates = tool == 'spray' || tool == 'airbrush';
      void paint(int i, int value) {
        // Ordinary strokes cover each pixel once, regardless of overlapping
        // stamps or symmetry. Spraying/airbrushing intentionally builds up.
        if (!accumulates && !painted.add(i)) return;
        c.pixels[i] = tool == 'eraser' || d.depth == 8
            ? value
            : over(c.pixels[i], value);
      }

      void pixel(int x, int y, int value, [Set<int>? stamp]) {
        for (final (xx, yy) in symmetry.points(x, y)) {
          final i = (yy - c.y) * c.width + xx - c.x;
          if (stamp != null && !stamp.add(i)) continue;
          if (effect) {
            covered.add(i);
          } else {
            paint(i, value);
          }
        }
      }

      int sourceColor(int x, int y) {
        final cx = x - c.x, cy = y - c.y;
        if (x < 0 ||
            y < 0 ||
            x >= d.width ||
            y >= d.height ||
            cx < 0 ||
            cy < 0 ||
            cx >= c.width ||
            cy >= c.height) {
          return 0;
        }
        return d.display(original[cy * c.width + cx], frame, layer);
      }

      void dot(int x, int y) {
        if (tool == 'airbrush') {
          final stamp = <int>{};
          // A soft circular dab, using integer radial falloff so both engines
          // produce identical pixels. Strength is flow per dab, not replacement.
          final radiusSquared = size * size;
          for (var oy = 0; oy < size; oy++) {
            for (var ox = 0; ox < size; ox++) {
              final dx = 2 * ox - size + 1, dy = 2 * oy - size + 1;
              final distance = dx * dx + dy * dy;
              if (distance >= radiusSquared) continue;
              final alpha =
                  ((color >> 24) * strength * (radiusSquared - distance) +
                      radiusSquared * 50) ~/
                  (radiusSquared * 100);
              if (alpha == 0) continue;
              final ink = (color & 0xffffff) | (alpha << 24);
              final px = x - size ~/ 2 + ox, py = y - size ~/ 2 + oy;
              if (d.depth == 8) {
                // Quantize the blended result rather than replacing an index
                // with a partially transparent palette entry.
                for (final (xx, yy) in symmetry.points(px, py)) {
                  final i = (yy - c.y) * c.width + xx - c.x;
                  if (!stamp.add(i)) continue;
                  c.pixels[i] = d.drawingColor(
                    over(d.display(c.pixels[i], frame, layer), ink),
                    frame,
                  );
                }
              } else {
                pixel(px, py, d.drawingColor(ink, frame), stamp);
              }
            }
          }
        } else if (tool == 'spray') {
          for (var i = 0; i < density; i++) {
            final ox = random() % size,
                oy = random() % size,
                dx = 2 * ox - size + 1,
                dy = 2 * oy - size + 1;
            if (dx * dx + dy * dy <= size * size) {
              pixel(x - size ~/ 2 + ox, y - size ~/ 2 + oy, v);
            }
          }
        } else {
          for (var j = y - size ~/ 2; j < y - size ~/ 2 + size; j++) {
            for (var i = x - size ~/ 2; i < x - size ~/ 2 + size; i++) {
              pixel(i, j, v);
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

      final first = points.first, last = points.last;
      if (tool == 'gradient') {
        // One canvas-wide field, independent of brush size and symmetry. Use
        // integer projection/interpolation for exact native/Dart parity.
        final dx = last.$1 - first.$1, dy = last.$2 - first.$2;
        final denominator = dx * dx + dy * dy;
        for (var y = 0; y < d.height; y++) {
          for (var x = 0; x < d.width; x++) {
            final position = ((x - first.$1) * dx + (y - first.$2) * dy).clamp(
              0,
              denominator,
            );
            var ink = 0;
            for (final shift in [0, 8, 16, 24]) {
              final from = color >> shift & 255, to = secondary >> shift & 255;
              ink |=
                  ((from * (denominator - position) +
                          to * position +
                          denominator ~/ 2) ~/
                      denominator) <<
                  shift;
            }
            final i = (y - c.y) * c.width + x - c.x;
            // Blend before indexed quantization; transparent ink is a no-op
            // that also preserves duplicate palette indices exactly.
            if (ink >> 24 == 0) continue;
            c.pixels[i] = d.drawingColor(
              over(d.display(c.pixels[i], frame, layer), ink),
              frame,
            );
          }
        }
      } else if (tool == 'fill') {
        final visited = Uint8List(c.pixels.length),
            region = Uint32List(d.width * d.height);
        for (final transform in symmetry.transforms) {
          final (x, y) = transform.point(d.width, d.height, first.$1, first.$2);
          final (dx, dy) = direction == 'horizontal'
              ? transform.vector(1, 0)
              : transform.vector(0, 1);
          final horizontal = dx != 0, reversed = dx < 0 || dy < 0;
          if (x < 0 || y < 0 || x >= d.width || y >= d.height) continue;
          final start = (y - c.y) * c.width + x - c.x, old = original[start];
          if (visited[start] != 0) continue;
          var count = 1, head = 0, minX = x, maxX = x, minY = y, maxY = y;
          region[0] = start;
          visited[start] = 1;
          while (head < count) {
            final i = region[head++];
            void push(int k) {
              final xx = c.x + k % c.width, yy = c.y + k ~/ c.width;
              if (xx >= 0 &&
                  yy >= 0 &&
                  xx < d.width &&
                  yy < d.height &&
                  visited[k] == 0 &&
                  original[k] == old) {
                visited[k] = 1;
                region[count++] = k;
                minX = math.min(minX, xx);
                maxX = math.max(maxX, xx);
                minY = math.min(minY, yy);
                maxY = math.max(maxY, yy);
              }
            }

            if (i % c.width > 0) push(i - 1);
            if (i % c.width < c.width - 1) push(i + 1);
            if (i >= c.width) push(i - c.width);
            if (i < c.pixels.length - c.width) push(i + c.width);
          }
          final denominator = horizontal ? maxX - minX : maxY - minY,
              mapped = <int, int>{};
          for (var n = 0; n < count; n++) {
            final i = region[n];
            var value = v;
            if (gradient && denominator > 0) {
              var p = horizontal
                  ? c.x + i % c.width - minX
                  : c.y + i ~/ c.width - minY;
              if (reversed) {
                p = denominator - p;
              }
              value = mapped.putIfAbsent(p, () {
                var rgb = 0;
                for (final shift in [0, 8, 16, 24]) {
                  final a = color >> shift & 255, b = secondary >> shift & 255;
                  rgb |=
                      ((a * (denominator - p) + b * p + denominator ~/ 2) ~/
                          denominator) <<
                      shift;
                }
                return d.drawingColor(rgb, frame);
              });
            }
            paint(i, value);
          }
        }
      } else if ((tool == 'rectangle' || tool == 'ellipse') &&
          a['filled'] == true) {
        final left = math.min(first.$1, last.$1),
            right = math.max(first.$1, last.$1),
            top = math.min(first.$2, last.$2),
            bottom = math.max(first.$2, last.$2),
            w = right - left + 1,
            h = bottom - top + 1;
        final bounds = symmetry.sourceBounds;
        for (
          var y = math.max(bounds.$2, top);
          y <= math.min(bounds.$4, bottom);
          y++
        ) {
          for (
            var x = math.max(bounds.$1, left);
            x <= math.min(bounds.$3, right);
            x++
          ) {
            final dx = 2 * x - left - right, dy = 2 * y - top - bottom;
            if (tool == 'rectangle' ||
                dx * dx * h * h + dy * dy * w * w <= w * w * h * h) {
              pixel(x, y, v);
            }
          }
        }
      } else if (tool == 'line') {
        line(first, last);
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
            steps = math.max(
              12,
              (2 *
                      math.pi *
                      math.max(
                        (last.$1 - first.$1).abs() / 2,
                        (last.$2 - first.$2).abs() / 2,
                      ))
                  .ceil(),
            );
        var previous = ((cx + rx).round(), cy.round());
        for (var i = 1; i <= steps; i++) {
          final t = 2 * math.pi * i / steps,
              p = (
                (cx + rx * math.cos(t)).round(),
                (cy + ry * math.sin(t)).round(),
              );
          line(previous, p);
          previous = p;
        }
      } else {
        dot(first.$1, first.$2);
        for (var i = 1; i < points.length; i++) {
          if (accumulates && points[i - 1] == points[i]) {
            dot(points[i].$1, points[i].$2);
          } else {
            line(points[i - 1], points[i], skipFirst: true);
          }
        }
      }
      if (tool == 'blur') {
        for (final i in covered) {
          final x = c.x + i % c.width,
              y = c.y + i ~/ c.width,
              base = sourceColor(x, y);
          var count = 0, sumA = 0, sumR = 0, sumG = 0, sumB = 0;
          for (
            var yy = math.max(0, y - 1);
            yy <= math.min(d.height - 1, y + 1);
            yy++
          ) {
            for (
              var xx = math.max(0, x - 1);
              xx <= math.min(d.width - 1, x + 1);
              xx++
            ) {
              final p = sourceColor(xx, yy), alpha = p >> 24;
              count++;
              sumA += alpha;
              sumR += (p >> 16 & 255) * alpha;
              sumG += (p >> 8 & 255) * alpha;
              sumB += (p & 255) * alpha;
            }
          }
          final blurredA = (sumA + count ~/ 2) ~/ count;
          final br = sumA == 0 ? 0 : (sumR + sumA ~/ 2) ~/ sumA,
              bg = sumA == 0 ? 0 : (sumG + sumA ~/ 2) ~/ sumA,
              bb = sumA == 0 ? 0 : (sumB + sumA ~/ 2) ~/ sumA;
          final baseWeight = (base >> 24) * (100 - strength),
              blurWeight = blurredA * strength,
              total = baseWeight + blurWeight;
          int ch(int shift, int value) => total == 0
              ? 0
              : ((base >> shift & 255) * baseWeight +
                        value * blurWeight +
                        total ~/ 2) ~/
                    total;
          final result =
              ((total + 50) ~/ 100) << 24 |
              ch(16, br) << 16 |
              ch(8, bg) << 8 |
              ch(0, bb);
          c.pixels[i] = d.drawingColor(result, frame);
        }
      } else if (tool == 'jumble') {
        // Swap with a local neighbour, including just outside a one-pixel
        // footprint. Shuffling only the covered mask made small brushes inert.
        // Swaps preserve the raw native-index histogram and hidden RGB data.
        for (final i in covered) {
          if (random() % 100 >= strength) continue;
          final x = c.x + i % c.width, y = c.y + i ~/ c.width;
          final neighbours = <int>[];
          for (
            var yy = math.max(0, y - 1);
            yy <= math.min(d.height - 1, y + 1);
            yy++
          ) {
            for (
              var xx = math.max(0, x - 1);
              xx <= math.min(d.width - 1, x + 1);
              xx++
            ) {
              final j = (yy - c.y) * c.width + xx - c.x;
              if (j != i && c.pixels[j] != c.pixels[i]) neighbours.add(j);
            }
          }
          if (neighbours.isEmpty) continue;
          final j = neighbours[random() % neighbours.length],
              value = c.pixels[i];
          c.pixels[i] = c.pixels[j];
          c.pixels[j] = value;
        }
      }
    });
  }

  void edit(Map<String, dynamic> a) {
    final action = a['action'];
    var nextFrame = frame, nextLayer = layer;
    _mutate((d) {
      switch (action) {
        case 'paletteAdd':
        case 'paletteEdit':
        case 'paletteMove':
        case 'paletteRemove':
        case 'palettePreset':
        case 'convertMode':
          applyPaletteAction(d, a, frame);
        case 'addLayer':
          require(d.layers.length < 256, 'Too many layers');
          d.layers.add(
            Layer(a['name'] as String? ?? 'Layer ${d.layers.length + 1}'),
          );
          for (final f in d.frames) {
            f.cels.add(null);
          }
          nextLayer = d.layers.length - 1;
        case 'deleteLayer':
          require(d.layers.length > 1, 'Keep at least one layer');
          d.layers.removeAt(layer);
          for (final f in d.frames) {
            f.cels.removeAt(layer);
          }
          nextLayer = layer.clamp(0, d.layers.length - 1);
        case 'renameLayer':
          final name = a['name'] as String;
          require(utf8.encode(name).length <= 65535, 'Layer name too long');
          d.layers[layer].name = name;
        case 'layerVisibility':
          d.layers[layer].visible =
              a['visible'] as bool? ?? !d.layers[layer].visible;
        case 'layerOpacity':
          d.layers[layer].opacity = _n(a, 'opacity', 255).clamp(0, 255);
        case 'moveLayer':
          final to = _n(a, 'to', layer);
          require(to >= 0 && to < d.layers.length, 'Invalid layer position');
          d.layers.insert(to, d.layers.removeAt(layer));
          for (final f in d.frames) {
            f.cels.insert(to, f.cels.removeAt(layer));
          }
          nextLayer = to;
        case 'transparentLayer':
          d.makeTransparent(layer);
        case 'addFrame':
        case 'duplicateFrame':
          d.addFrame(frame, action == 'duplicateFrame');
          nextFrame = frame + 1;
        case 'deleteFrame':
          d.removeFrame(frame);
          nextFrame = frame.clamp(0, d.frames.length - 1);
        case 'frameDuration':
          d.frames[frame].duration = _n(a, 'duration', 100).clamp(1, 65535);
        case 'addTag':
        case 'updateTag':
        case 'duplicateTag':
          int integer(String key, int fallback) {
            final value = a[key];
            if (value == null) return fallback;
            require(value is int, 'Tag $key must be an integer');
            return value as int;
          }
          Tag? original;
          if (action != 'addTag') {
            final index = integer('index', -1);
            require(index >= 0 && index < d.tags.length, 'Invalid tag index');
            original = d.tags[index];
          }
          final from = integer('from', original?.from ?? frame),
              to = integer('to', original?.to ?? frame);
          final direction = integer('direction', original?.direction ?? 0),
              repeat = integer('repeat', original?.repeat ?? 0);
          require(
            from >= 0 && from <= to && to < d.frames.length,
            'Invalid tag range',
          );
          require(
            direction >= 0 && direction <= 3,
            'Tag direction must be 0–3',
          );
          require(repeat >= 0 && repeat <= 65535, 'Tag repeat must be 0–65535');
          final name = a['name'] ?? original?.name ?? 'Animation';
          require(
            name is String && utf8.encode(name).length <= 65535,
            'Tag name exceeds 65535 UTF-8 bytes',
          );
          final next =
              original?.copy() ??
              Tag(
                from,
                to,
                name as String,
                color: Uint8List.fromList([100, 100, 100]),
              );
          next.name = name as String;
          next.from = from;
          next.to = to;
          next.direction = direction;
          next.repeat = repeat;
          if (action == 'updateTag') {
            d.tags[integer('index', -1)] = next;
          } else {
            require(d.tags.length < 65535, 'Too many tags');
            d.tags.add(next);
          }
        case 'deleteTag':
          d.tags.removeAt(_n(a, 'index', 0));
        case 'userData':
          final text = a['text'] as String? ?? '';
          require(
            utf8.encode(text).length <= 65535,
            'Metadata exceeds 65535 UTF-8 bytes',
          );
          UserData changed(UserData? old) =>
              (old?.copy() ?? UserData())..text = text;
          switch (a['target']) {
            case 'sprite':
              d.data = changed(d.data);
            case 'layer':
              d.layers[layer].data = changed(d.layers[layer].data);
            case 'cel':
              final c = d.editable(frame, layer);
              c.data = changed(c.data);
            case 'tag':
              final t = d.tags[_n(a, 'index', 0)];
              t.data = changed(t.data);
            default:
              throw const FormatException('Unknown metadata target');
          }
        case 'resize':
          final w = _n(a, 'width', d.width), h = _n(a, 'height', d.height);
          require(
            w >= 1 && h >= 1 && w <= 2048 && h <= 2048 && w * h <= maxPixels,
            'Invalid dimensions',
          );
          d.width = w;
          d.height = h;
        case 'flipHorizontal':
        case 'flipVertical':
          final c = d.editable(frame, layer),
              old = Uint32List.fromList(d.resolved(frame, layer)!.pixels);
          for (var y = 0; y < d.height; y++) {
            for (var x = 0; x < d.width; x++) {
              final sx = action == 'flipHorizontal' ? d.width - 1 - x : x,
                  sy = action == 'flipVertical' ? d.height - 1 - y : y;
              c.pixels[(y - c.y) * c.width + x - c.x] =
                  old[(sy - c.y) * c.width + sx - c.x];
            }
          }
        default:
          throw FormatException('Unknown edit action: $action');
      }
    });
    frame = nextFrame;
    layer = nextLayer;
  }

  Map<String, dynamic> state() => {
    'width': document.width,
    'height': document.height,
    'frame': frame,
    'layer': layer,
    'depth': document.depth,
    'transparentIndex': document.transparentIndex,
    'paletteNames': List.generate(
      document.frames[frame].palette.length,
      (index) => document.frames[frame].paletteNames[index],
    ),
    'dirty': dirty,
    'canUndo': _undo.isNotEmpty,
    'canRedo': _redo.isNotEmpty,
    'recoveryAvailable': recoveryAvailable,
    'pixels': rgbaBytes(document.composite(frame)),
    'previousPixels': frame > 0
        ? rgbaBytes(document.composite(frame - 1))
        : null,
    'palette': document.frames[frame].palette,
    'layers': document.layers
        .map(
          (l) => {
            'name': l.name,
            'visible': l.visible,
            'opacity': l.opacity,
            'editable': l.flags & 2 != 0,
            'background': l.flags & 8 != 0,
          },
        )
        .toList(),
    'frames': document.frames.map((f) => {'duration': f.duration}).toList(),
    'tags': document.tags
        .map(
          (t) => {
            'name': t.name,
            'from': t.from,
            'to': t.to,
            'direction': t.direction,
            'repeat': t.repeat,
            'text': t.data?.text,
          },
        )
        .toList(),
    'userData': {
      'sprite': document.data?.text,
      'layer': document.layers[layer].data?.text,
      'cel': document.resolved(frame, layer)?.data?.text,
    },
  };
}
