import 'dart:math' as math;
import 'dart:typed_data';

const maxPixels = 4194304;
const defaultPalette = <int>[
  0xff000000,
  0xffffffff,
  0xff9e9e9e,
  0xffe53935,
  0xffff9800,
  0xffffeb3b,
  0xff66bb6a,
  0xff26c6da,
  0xff42a5f5,
  0xff7e57c2,
  0xffec407a,
  0xff795548,
];
void require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}

class UserData {
  String? text;
  int? color;
  Uint8List? properties;
  UserData({this.text, this.color, this.properties});
  UserData copy() => UserData(
    text: text,
    color: color,
    properties: properties == null ? null : Uint8List.fromList(properties!),
  );
}

class Layer {
  String name;
  bool visible;
  int opacity, flags;
  Uint8List? uuid;
  UserData? data;
  Layer(
    this.name, {
    this.visible = true,
    this.opacity = 255,
    this.flags = 3,
    this.uuid,
    this.data,
  });
  Layer copy() => Layer(
    name,
    visible: visible,
    opacity: opacity,
    flags: flags,
    uuid: uuid,
    data: data?.copy(),
  );
}

class Cel {
  int x, y, width, height, opacity;
  Uint32List pixels;
  int? link;
  UserData? data;
  Cel(
    this.x,
    this.y,
    this.width,
    this.height,
    this.pixels, {
    this.opacity = 255,
    this.link,
    this.data,
  });
  Cel copy() => Cel(
    x,
    y,
    width,
    height,
    Uint32List.fromList(pixels),
    opacity: opacity,
    link: link,
    data: data?.copy(),
  );
}

class RawChunk {
  final int type;
  final Uint8List bytes;
  RawChunk(this.type, this.bytes);
}

class Frame {
  int duration;
  List<Cel?> cels;
  List<RawChunk> metadata;
  List<int> palette;
  Map<int, int> palettePatches;
  Map<int, String> paletteNames;
  Frame({
    this.duration = 100,
    List<Cel?>? cels,
    List<RawChunk>? metadata,
    List<int>? palette,
    Map<int, int>? palettePatches,
    Map<int, String>? paletteNames,
  }) : cels = cels ?? [],
       metadata = metadata ?? [],
       palette = palette ?? List.of(defaultPalette),
       palettePatches = palettePatches ?? {},
       paletteNames = paletteNames ?? {};
  Frame copy() => Frame(
    duration: duration,
    cels: cels.map((c) => c?.copy()).toList(),
    metadata: List.of(metadata),
    palette: List.of(palette),
    palettePatches: Map.of(palettePatches),
    paletteNames: Map.of(paletteNames),
  );
}

class Tag {
  int from, to, direction, repeat;
  Uint8List color;
  String name;
  UserData? data;
  Tag(
    this.from,
    this.to,
    this.name, {
    this.direction = 0,
    this.repeat = 0,
    Uint8List? color,
    this.data,
  }) : color = color ?? Uint8List(3);
  Tag copy() => Tag(
    from,
    to,
    name,
    direction: direction,
    repeat: repeat,
    color: Uint8List.fromList(color),
    data: data?.copy(),
  );
}

class SpriteDocument {
  int width, height, depth, transparentIndex;
  List<Layer> layers;
  List<Frame> frames;
  List<Tag> tags;
  Uint8List? header;
  UserData? data;
  SpriteDocument(
    this.width,
    this.height,
    this.layers,
    this.frames, {
    this.depth = 32,
    this.transparentIndex = 0,
    List<Tag>? tags,
    this.header,
    this.data,
  }) : tags = tags ?? [];
  factory SpriteDocument.create([int width = 32, int height = 32]) {
    require(
      width >= 1 &&
          height >= 1 &&
          width <= 2048 &&
          height <= 2048 &&
          width * height <= maxPixels,
      'Canvas must be 1–2048 pixels',
    );
    return SpriteDocument(
      width,
      height,
      [Layer('Layer 1')],
      [
        Frame(cels: [null]),
      ],
    );
  }
  SpriteDocument copy() => SpriteDocument(
    width,
    height,
    layers.map((l) => l.copy()).toList(),
    frames.map((f) => f.copy()).toList(),
    depth: depth,
    transparentIndex: transparentIndex,
    tags: tags.map((t) => t.copy()).toList(),
    header: header == null ? null : Uint8List.fromList(header!),
    data: data?.copy(),
  );
  Cel? resolved(int frame, int layer) {
    final original = frames[frame].cels[layer];
    if (original == null) return null;
    var c = original;
    final seen = <int>{};
    var f = frame;
    while (c.link != null) {
      require(seen.add(f), 'Cyclic linked cel');
      f = c.link!;
      require(f >= 0 && f < frames.length, 'Linked cel outside document');
      c =
          frames[f].cels[layer] ??
          (throw const FormatException('Missing linked cel'));
    }
    if (original.link == null) return original;
    return Cel(
      original.x,
      original.y,
      c.width,
      c.height,
      c.pixels,
      opacity: original.opacity,
      data: original.data,
    );
  }

  void detachLinks() {
    for (var f = 0; f < frames.length; f++) {
      for (var l = 0; l < layers.length; l++) {
        if (frames[f].cels[l]?.link != null) {
          frames[f].cels[l] = resolved(f, l)?.copy();
        }
      }
    }
  }

  Cel editable(int frame, int layer) {
    final c = resolved(frame, layer);
    final x = math.min(0, c?.x ?? 0), y = math.min(0, c?.y ?? 0);
    final w = math.max(width, (c?.x ?? 0) + (c?.width ?? 0)) - x,
        h = math.max(height, (c?.y ?? 0) + (c?.height ?? 0)) - y;
    require(
      w > 0 && h > 0 && w * h <= maxPixels,
      'Off-canvas cel exceeds editing limits',
    );
    final p = Uint32List(w * h);
    if (depth == 8) p.fillRange(0, p.length, transparentIndex);
    final out = Cel(
      x,
      y,
      w,
      h,
      p,
      opacity: c?.opacity ?? 255,
      data: c?.data?.copy(),
    );
    if (c != null) {
      for (var j = 0; j < c.height; j++) {
        for (var i = 0; i < c.width; i++) {
          p[(j + c.y - y) * w + i + c.x - x] = c.pixels[j * c.width + i];
        }
      }
    }
    detachLinks();
    frames[frame].cels[layer] = out;
    return out;
  }

  int display(int value, int frame, int layer) => depth != 8
      ? value
      : (value == transparentIndex && layers[layer].flags & 8 == 0
            ? 0
            : frames[frame].palette[value]);
  int drawingColor(int color, int frame, {bool erase = false}) {
    if (erase || color >> 24 == 0) return depth == 8 ? transparentIndex : 0;
    if (depth == 16) {
      final v =
          (((color >> 16 & 255) * 299 +
              (color >> 8 & 255) * 587 +
              (color & 255) * 114 +
              500) ~/
          1000);
      return (color & 0xff000000) | (v * 0x010101);
    }
    if (depth == 8) {
      var best = transparentIndex, dist = 1 << 40;
      for (var i = 0; i < frames[frame].palette.length; i++) {
        if (i == transparentIndex) continue;
        var d = 0;
        for (final shift in [0, 8, 16, 24]) {
          final delta =
              (frames[frame].palette[i] >> shift & 255) -
              (color >> shift & 255);
          d += delta * delta;
        }
        if (d < dist) {
          dist = d;
          best = i;
        }
      }
      return best;
    }
    return color;
  }

  Uint32List composite(int frame) {
    final out = Uint32List(width * height);
    for (var l = 0; l < layers.length; l++) {
      if (!layers[l].visible) continue;
      final c = resolved(frame, l);
      if (c == null) continue;
      final opacity = (layers[l].opacity * c.opacity + 127) ~/ 255;
      for (var y = 0; y < c.height; y++) {
        for (var x = 0; x < c.width; x++) {
          final dx = x + c.x, dy = y + c.y;
          if (dx >= 0 && dy >= 0 && dx < width && dy < height) {
            final i = dy * width + dx;
            out[i] = over(
              out[i],
              display(c.pixels[y * c.width + x], frame, l),
              opacity,
            );
          }
        }
      }
    }
    return out;
  }

  void addFrame(int after, bool duplicate) {
    require(frames.length < 4096, 'Too many frames');
    detachLinks();
    final f = duplicate
        ? frames[after].copy()
        : Frame(
            cels: List.filled(layers.length, null),
            palette: List.of(frames[after].palette),
            paletteNames: Map.of(frames[after].paletteNames),
          );
    f.metadata.removeWhere((c) => c.type == 0x2007);
    frames.insert(after + 1, f);
    for (final t in tags) {
      if (t.from > after) t.from++;
      if (t.to > after) t.to++;
    }
  }

  void removeFrame(int index) {
    require(frames.length > 1, 'Keep at least one frame');
    detachLinks();
    final global = frames.first.metadata
        .where((c) => c.type == 0x2007)
        .toList();
    frames.removeAt(index);
    if (index == 0) frames.first.metadata.insertAll(0, global);
    tags.removeWhere((t) => t.from == index && t.to == index);
    for (final t in tags) {
      if (t.from > index) t.from--;
      if (t.to >= index) t.to--;
    }
  }

  void makeTransparent(int layer) {
    if (layers[layer].flags & 8 == 0) return;
    if (depth == 8) {
      final plans = <(int, Cel, int, bool)>[];
      for (var f = 0; f < frames.length; f++) {
        final c = resolved(f, layer)?.copy();
        if (c == null || !c.pixels.contains(transparentIndex)) continue;
        final pal = frames[f].palette;
        var index = -1;
        for (var i = 0; i < pal.length; i++) {
          if (i != transparentIndex && pal[i] == pal[transparentIndex]) {
            index = i;
            break;
          }
        }
        require(
          index >= 0 || pal.length < 256,
          'Indexed palette is full; convert to RGBA in Aseprite first',
        );
        plans.add((f, c, index >= 0 ? index : pal.length, index < 0));
      }
      for (final p in plans) {
        final f = frames[p.$1];
        if (p.$4) {
          f.palette.add(f.palette[transparentIndex]);
          f.palettePatches[p.$3] = f.palette.last;
        }
        for (var i = 0; i < p.$2.pixels.length; i++) {
          if (p.$2.pixels[i] == transparentIndex) p.$2.pixels[i] = p.$3;
        }
        p.$2.link = null;
        f.cels[layer] = p.$2;
      }
    }
    layers[layer].flags &= ~8;
  }
}

// Aseprite/asefile normal blend rounding, including transparent hidden RGB.
int over(int dst, int src, [int opacity = 255]) {
  int mul(int a, int b) {
    final t = a * b + 128;
    return ((t >> 8) + t) >> 8;
  }

  final ba = dst >> 24, sa = src >> 24;
  if (ba == 0) return (src & 0xffffff) | (mul(sa, opacity) << 24);
  if (sa == 0) return dst;
  final a = mul(sa, opacity), outA = a + ba - mul(ba, a);
  int channel(int shift) {
    final back = dst >> shift & 255, front = src >> shift & 255;
    return back + (front - back) * a ~/ outA;
  }

  return outA << 24 | channel(16) << 16 | channel(8) << 8 | channel(0);
}

Uint8List rgbaBytes(Uint32List pixels) {
  final b = Uint8List(pixels.length * 4);
  for (var i = 0; i < pixels.length; i++) {
    final c = pixels[i];
    b[i * 4] = c >> 16;
    b[i * 4 + 1] = c >> 8;
    b[i * 4 + 2] = c;
    b[i * 4 + 3] = c >> 24;
  }
  return b;
}
