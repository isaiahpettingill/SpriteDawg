import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'aseprite.dart';
import 'document.dart';

/// Portable Linux editing backend with exactly the Android channel contract.
/// File picking, atomic recovery and PNG encoding belong to the platform adapter.
class EditorEngine {
  SpriteDocument document = SpriteDocument.create();
  int frame = 0, layer = 0;
  bool dirty = false, recoveryAvailable = false;
  final List<SpriteDocument> _undo = [], _redo = [];
  void replace(SpriteDocument d, {bool unsaved = false}) {
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
      case 'init':
      case 'state':
        break;
      case 'new':
        replace(
          SpriteDocument.create(_n(args, 'width', 32), _n(args, 'height', 32)),
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
          _redo.add(document);
          document = _undo.removeLast();
          dirty = true;
          _clamp();
        }
        break;
      case 'redo':
        if (_redo.isNotEmpty) {
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

  void _clamp() {
    frame = frame.clamp(0, document.frames.length - 1);
    layer = layer.clamp(0, document.layers.length - 1);
  }

  void _mutate(void Function(SpriteDocument) change) {
    final next = document.copy();
    change(next);
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
            _undo.fold<int>(0, (n, d) => n + bytes(d)) > 48 * 1024 * 1024)) {
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
        'line',
        'rectangle',
        'ellipse',
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
    final size = _n(a, 'size', 1).clamp(1, 32),
        color = _n(a, 'color', 0xff000000);
    require(document.layers[layer].visible, 'Show this layer before drawing');
    require(document.layers[layer].flags & 2 != 0, 'This layer is locked');
    require(
      tool != 'eraser' || document.layers[layer].flags & 8 == 0,
      'Convert background layer to transparent before erasing',
    );
    _mutate((d) {
      final c = d.editable(frame, layer),
          v = d.drawingColor(color, frame, erase: tool == 'eraser');
      void dot(int x, int y) {
        for (var j = y - size ~/ 2; j < y - size ~/ 2 + size; j++) {
          for (var i = x - size ~/ 2; i < x - size ~/ 2 + size; i++) {
            if (i >= 0 && j >= 0 && i < d.width && j < d.height) {
              c.pixels[(j - c.y) * c.width + i - c.x] = v;
            }
          }
        }
      }

      void line((int, int) a, (int, int) b) {
        var x = a.$1, y = a.$2;
        final dx = (b.$1 - x).abs(),
            dy = -(b.$2 - y).abs(),
            sx = x < b.$1 ? 1 : -1,
            sy = y < b.$2 ? 1 : -1;
        var e = dx + dy;
        while (true) {
          dot(x, y);
          if (x == b.$1 && y == b.$2) break;
          final e2 = 2 * e;
          if (e2 >= dy) {
            e += dy;
            x += sx;
          }
          if (e2 <= dx) {
            e += dx;
            y += sy;
          }
        }
      }

      final first = points.first, last = points.last;
      if (tool == 'fill') {
        final x = first.$1, y = first.$2;
        if (x < 0 || y < 0 || x >= d.width || y >= d.height) return;
        final start = (y - c.y) * c.width + x - c.x, old = c.pixels[start];
        if (old == v) return;
        final stack = <int>[start];
        c.pixels[start] = v;
        while (stack.isNotEmpty) {
          final i = stack.removeLast();
          void push(int k) {
            final xx = c.x + k % c.width, yy = c.y + k ~/ c.width;
            if (xx >= 0 &&
                yy >= 0 &&
                xx < d.width &&
                yy < d.height &&
                c.pixels[k] == old) {
              c.pixels[k] = v;
              stack.add(k);
            }
          }

          if (i % c.width > 0) push(i - 1);
          if (i % c.width < c.width - 1) push(i + 1);
          if (i >= c.width) push(i - c.width);
          if (i < c.pixels.length - c.width) push(i + c.width);
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
            cy = (first.$2 + last.$2) / 2;
        final steps = math.max(12, (2 * math.pi * math.max(rx, ry)).ceil());
        var prev = ((cx + rx).round(), cy.round());
        for (var i = 1; i <= steps; i++) {
          final t = 2 * math.pi * i / steps,
              p = (
                (cx + rx * math.cos(t)).round(),
                (cy + ry * math.sin(t)).round(),
              );
          line(prev, p);
          prev = p;
        }
      } else {
        line(first, first);
        for (var i = 1; i < points.length; i++) {
          line(points[i - 1], points[i]);
        }
      }
    });
  }

  void edit(Map<String, dynamic> a) {
    final action = a['action'];
    var nextFrame = frame, nextLayer = layer;
    _mutate((d) {
      switch (action) {
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
          final from = _n(a, 'from', frame), to = _n(a, 'to', frame);
          require(
            from >= 0 &&
                from < d.frames.length &&
                to >= from &&
                to < d.frames.length,
            'Invalid tag range',
          );
          final name = a['name'] as String? ?? 'Animation';
          require(utf8.encode(name).length <= 65535, 'Tag name too long');
          d.tags.add(
            Tag(
              from,
              to,
              name,
              direction: _n(a, 'direction', 0).clamp(0, 3),
              color: Uint8List.fromList([100, 100, 100]),
            ),
          );
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
