/// A conservative Aseprite codec. Unsupported rendering chunks are refused,
/// never silently flattened or dropped. Palette chunks and typed properties
/// retain their original bytes; editing text does not replace typed properties.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'document.dart';
import 'deflate_boundary.dart';

class _Reader {
  final Uint8List bytes;
  int pos = 0;
  _Reader(List<int> b) : bytes = Uint8List.fromList(b);
  int get left => bytes.length - pos;
  Uint8List take(int n) {
    require(n >= 0 && n <= left, 'Truncated Aseprite data');
    final b = Uint8List.sublistView(bytes, pos, pos + n);
    pos += n;
    return b;
  }

  int u8() => take(1)[0];
  int u16() => u8() | u8() << 8;
  int s16() {
    final n = u16();
    return n >= 32768 ? n - 65536 : n;
  }

  int u32() {
    final n = u16() | u16() << 16;
    require(n <= 0x7fffffff, 'Field exceeds safe limit');
    return n;
  }

  String str() => utf8.decode(take(u16()));
  void zero(int n) =>
      require(take(n).every((b) => b == 0), 'Unsupported reserved data');
  void end() => require(left == 0, 'Unexpected trailing chunk data');
}

class _Writer {
  final BytesBuilder _b = BytesBuilder(copy: false);
  void b(int v) => _b.addByte(v & 255);
  void w(int v) {
    b(v);
    b(v >> 8);
  }

  void d(int v) {
    w(v);
    w(v >> 16);
  }

  void bytes(List<int> b) => _b.add(b);
  void zeros(int n) => bytes(Uint8List(n));
  void str(String s) {
    final b = utf8.encode(s);
    require(b.length <= 65535, 'Text exceeds 65535 UTF-8 bytes');
    w(b.length);
    bytes(b);
  }

  Uint8List result() => _b.toBytes();
}

class AsepriteCodec {
  static const maxFile = 64 * 1024 * 1024;
  static SpriteDocument decode(Uint8List bytes) {
    require(
      bytes.length >= 128 && bytes.length <= maxFile,
      'File is truncated or exceeds 64 MiB',
    );
    final r = _Reader(bytes);
    require(r.u32() == bytes.length, 'Incorrect file size');
    require(r.u16() == 0xa5e0, 'Not an Aseprite file');
    final count = r.u16(),
        w = r.u16(),
        h = r.u16(),
        depth = r.u16(),
        flags = r.u32(),
        speed = r.u16();
    require(
      count >= 1 &&
          count <= 4096 &&
          w >= 1 &&
          h >= 1 &&
          w <= 2048 &&
          h <= 2048 &&
          w * h <= maxPixels,
      'Sprite exceeds safe dimensions',
    );
    require([8, 16, 32].contains(depth), 'Unsupported color depth');
    require(flags & 7 == flags, 'Unsupported header flags');
    r.zero(8);
    final transparent = r.u8();
    r.take(3);
    r.u16();
    final pw = r.u8(), ph = r.u8();
    require(pw == 0 || ph == 0 || pw == ph, 'Non-square pixels unsupported');
    r.take(8);
    r.zero(84);
    final d = SpriteDocument(
      w,
      h,
      [],
      [],
      header: Uint8List.fromList(bytes.sublist(0, 128)),
      depth: depth,
      transparentIndex: transparent,
    );
    var currentPalette = List.filled(256, 0xff000000);
    var paletteSeen = false, totalPixels = 0;
    var currentNames = <int, String>{};
    UserData? spriteData;
    for (var fi = 0; fi < count; fi++) {
      final size = r.u32();
      require(size >= 16 && size <= r.left + 4, 'Invalid frame size');
      final fr = _Reader(r.take(size - 4));
      require(fr.u16() == 0xf1fa, 'Invalid frame magic');
      final old = fr.u16(), duration = fr.u16();
      fr.zero(2);
      final newer = fr.u32(), chunks = newer == 0 ? old : newer;
      require(
        chunks <= 100000 && chunks <= fr.left ~/ 6,
        'Invalid chunk count',
      );
      final f = Frame(
        duration: duration == 0 ? (speed < 1 ? 1 : speed) : duration,
      );
      d.frames.add(f);
      final initial = List<int>.of(currentPalette);
      final initialNames = Map<int, String>.of(currentNames);
      var modern = false;
      final pending = <int, Cel>{};
      void Function(UserData)? attach;
      var tagTargets = <Tag>[], tagAt = 0;
      for (var ci = 0; ci < chunks; ci++) {
        final cs = fr.u32(), type = fr.u16();
        require(cs >= 6 && cs - 6 <= fr.left, 'Invalid chunk size');
        final raw = fr.take(cs - 6), c = _Reader(raw);
        if (type != 0x2020) {
          attach = null;
          tagTargets = [];
          tagAt = 0;
        }
        switch (type) {
          case 0x2004:
            require(fi == 0, 'Animated layer definitions unsupported');
            final lf = c.u16(), lt = c.u16(), level = c.u16();
            c.take(4);
            final blend = c.u16(), opacity = c.u8();
            c.zero(3);
            final name = c.str();
            require(
              lt == 0 && level == 0,
              'Group and tilemap layers cannot be safely edited',
            );
            require(blend == 0, 'Unsupported layer blend mode');
            require(lf & 64 == 0 && lf & 127 == lf, 'Unsupported layer flags');
            final layer = Layer(
              name,
              visible: lf & 1 != 0,
              opacity: flags & 1 != 0 ? opacity : 255,
              flags: lf,
              uuid: flags & 4 != 0 ? c.take(16) : null,
            );
            d.layers.add(layer);
            attach = (u) => layer.data = u;
            require(d.layers.length <= 256, 'Too many layers');
          case 0x2005:
            final li = c.u16(),
                x = c.s16(),
                y = c.s16(),
                opacity = c.u8(),
                ct = c.u16(),
                z = c.s16();
            c.zero(5);
            require(z == 0, 'Cel z-index changes unsupported');
            require(!pending.containsKey(li), 'Duplicate cel');
            late Cel cel;
            if (ct == 1) {
              cel = Cel(
                x,
                y,
                0,
                0,
                Uint32List(0),
                opacity: opacity,
                link: c.u16(),
              );
            } else {
              require(
                ct == 0 || ct == 2,
                'Tilemap or unknown cel type unsupported',
              );
              final cw = c.u16(), ch = c.u16(), n = cw * ch;
              require(
                cw > 0 && ch > 0 && n <= maxPixels,
                'Invalid cel dimensions',
              );
              totalPixels += n;
              require(
                totalPixels <= 16777216,
                'Decoded document exceeds 64 MiB pixel budget',
              );
              final expected = n * (depth ~/ 8), payload = c.take(c.left);
              final data = ct == 0 ? payload : _inflate(payload, expected);
              require(data.length == expected, 'Incorrect cel pixel length');
              final pr = _Reader(data), pixels = Uint32List(n);
              for (var p = 0; p < n; p++) {
                if (depth == 8) {
                  pixels[p] = pr.u8();
                } else if (depth == 16) {
                  final v = pr.u8(), a = pr.u8();
                  pixels[p] = a << 24 | v * 0x010101;
                } else {
                  final red = pr.u8(),
                      green = pr.u8(),
                      blue = pr.u8(),
                      a = pr.u8();
                  pixels[p] = a << 24 | red << 16 | green << 8 | blue;
                }
              }
              cel = Cel(x, y, cw, ch, pixels, opacity: opacity);
            }
            pending[li] = cel;
            attach = (u) => cel.data = u;
          case 0x2018:
            require(d.tags.isEmpty, 'Multiple tag definitions unsupported');
            final n = c.u16();
            c.zero(8);
            for (var t = 0; t < n; t++) {
              final from = c.u16(), to = c.u16(), dir = c.u8(), rep = c.u16();
              c.zero(6);
              final color = c.take(3);
              c.zero(1);
              final name = c.str();
              require(
                from <= to && to < count && dir <= 3,
                'Invalid animation tag',
              );
              d.tags.add(
                Tag(from, to, name, direction: dir, repeat: rep, color: color),
              );
            }
            tagTargets = List.of(d.tags);
          case 0x2019:
            if (!modern) {
              currentPalette = List.of(initial);
              currentNames = Map.of(initialNames);
              modern = true;
            }
            final n = c.u32(), first = c.u32(), last = c.u32();
            c.zero(8);
            require(
              n >= 1 && n <= 65536 && first <= last && last < n,
              'Invalid palette range',
            );
            require(
              depth != 8 || n <= 256,
              'Indexed palette exceeds 256 entries',
            );
            currentPalette = List.generate(
              n,
              (i) => i < currentPalette.length ? currentPalette[i] : 0,
            );
            for (var i = first; i <= last; i++) {
              final ef = c.u16();
              require(ef & 1 == ef, 'Unknown palette flags');
              final red = c.u8(), green = c.u8(), blue = c.u8(), a = c.u8();
              currentPalette[i] = a << 24 | red << 16 | green << 8 | blue;
              if (ef & 1 != 0) {
                currentNames[i] = c.str();
              } else {
                currentNames.remove(i);
              }
            }
            paletteSeen = true;
            f.metadata.add(RawChunk(type, raw));
            attach = (u) => spriteData = u;
          case 4:
          case 17:
            final packets = c.u16();
            var index = 0;
            for (var p = 0; p < packets; p++) {
              index += c.u8();
              var n = c.u8();
              if (n == 0) n = 256;
              require(index + n <= 256, 'Invalid legacy palette');
              for (var j = 0; j < n; j++) {
                int channel() {
                  final v = c.u8();
                  require(type != 17 || v <= 63, 'Invalid six-bit palette');
                  return type == 17 ? (v << 2) | (v >> 4) : v;
                }

                final red = channel(), green = channel(), blue = channel();
                if (!modern && index < currentPalette.length) {
                  currentPalette[index] =
                      0xff000000 | red << 16 | green << 8 | blue;
                }
                index++;
              }
            }
            paletteSeen = true;
            f.metadata.add(RawChunk(type, raw));
            attach = (u) => spriteData = u;
          case 0x2007:
            final profile = c.u16(), pf = c.u16(), gamma = c.u32();
            c.zero(8);
            require(
              profile <= 1 && (pf == 0 || (pf == 1 && gamma == 144179)),
              'ICC/custom gamma profiles cannot render safely',
            );
            f.metadata.add(RawChunk(type, raw));
          case 0x2020:
            final u = _readData(c);
            if (tagTargets.isNotEmpty) {
              require(tagAt < tagTargets.length, 'Excess tag user data');
              tagTargets[tagAt++].data = u;
            } else {
              require(
                attach != null,
                'Unassociated user data cannot be preserved',
              );
              attach!(u);
              attach = null;
            }
          default:
            throw FormatException(
              'Unsupported chunk 0x${type.toRadixString(16)}; editing refused to preserve metadata',
            );
        }
        c.end();
      }
      fr.end();
      require(
        pending.keys.every((i) => i >= 0 && i < d.layers.length),
        'Cel references missing layer',
      );
      f.cels = List.generate(d.layers.length, (i) => pending[i]);
      f.palette = List.of(currentPalette);
      f.paletteNames = Map.of(currentNames)
        ..removeWhere((i, _) => i >= currentPalette.length);
    }
    r.end();
    require(d.layers.isNotEmpty, 'Sprite has no layers');
    require(depth != 8 || paletteSeen, 'Indexed file has no explicit palette');
    for (var f = 0; f < d.frames.length; f++) {
      for (var l = 0; l < d.layers.length; l++) {
        final c = d.frames[f].cels[l];
        if (c == null) continue;
        if (c.link != null) {
          require(
            c.link! >= 0 && c.link! < f,
            'Linked cel must reference earlier frame',
          );
        }
        final resolved = d.resolved(f, l)!;
        if (depth == 8) {
          require(
            resolved.pixels.every((v) => v < d.frames[f].palette.length),
            'Pixel index outside palette',
          );
        }
      }
    }
    d.data = spriteData;
    return d;
  }

  static UserData _readData(_Reader c) {
    final flags = c.u32();
    require(flags & 7 == flags, 'Unknown user data flags');
    final text = flags & 1 != 0 ? c.str() : null;
    int? color;
    if (flags & 2 != 0) {
      final r = c.u8(), g = c.u8(), b = c.u8(), a = c.u8();
      color = a << 24 | r << 16 | g << 8 | b;
    }
    Uint8List? properties;
    if (flags & 4 != 0) {
      properties = c.take(c.left);
      require(properties.length >= 8, 'Truncated typed properties');
      final pr = _Reader(properties);
      require(pr.u32() == properties.length, 'Invalid typed properties length');
      _validateProperties(pr);
      // Typed property payload remains byte-for-byte intact.
    }
    return UserData(text: text, color: color, properties: properties);
  }

  static void _validateProperties(_Reader r) {
    final maps = r.u32();
    require(maps <= 1, 'Multiple property maps unsupported');
    void skip(int type, int depth) {
      require(depth <= 128, 'Properties exceed nesting limit');
      switch (type) {
        case 1:
        case 2:
        case 3:
          r.take(1);
        case 4:
        case 5:
          r.take(2);
        case 6:
        case 7:
        case 10:
        case 11:
          r.take(4);
        case 8:
        case 9:
        case 12:
        case 14:
        case 15:
          r.take(8);
        case 16:
        case 19:
          r.take(16);
        case 13:
          r.str();
        case 17:
          final count = r.u32(), element = r.u16();
          require(count <= r.left, 'Invalid vector count');
          for (var i = 0; i < count; i++) {
            skip(element == 0 ? r.u16() : element, depth + 1);
          }
        case 18:
          final count = r.u32();
          require(count <= r.left ~/ 4, 'Invalid nested property count');
          for (var i = 0; i < count; i++) {
            r.str();
            skip(r.u16(), depth + 1);
          }
        default:
          throw FormatException('Unsupported property type $type');
      }
    }

    if (maps == 1) {
      require(r.u32() == 0, 'Extension properties need external references');
      final count = r.u32();
      require(count <= r.left ~/ 4, 'Invalid property count');
      for (var i = 0; i < count; i++) {
        r.str();
        skip(r.u16(), 0);
      }
    }
    r.end();
  }

  static Uint8List _inflate(Uint8List payload, int expected) {
    validateZlib(payload, expected);
    final out = BytesBuilder(copy: false);
    var count = 0;
    final sink = _LimitedSink(expected, (b) {
      count += b.length;
      out.add(b);
    });
    final decoder = ZLibDecoder().startChunkedConversion(sink);
    for (var offset = 0; offset < payload.length; offset += 1024) {
      decoder.add(
        payload.sublist(offset, (offset + 1024).clamp(0, payload.length)),
      );
    }
    decoder.close();
    require(count == expected, 'Incorrect zlib cel length');
    return out.toBytes();
  }

  static Uint8List _chunk(int type, void Function(_Writer) write) {
    final data = _Writer();
    write(data);
    final b = data.result(), w = _Writer();
    w.d(b.length + 6);
    w.w(type);
    w.bytes(b);
    return w.result();
  }

  static Uint8List? _user(UserData? u) => u == null
      ? null
      : _chunk(0x2020, (w) {
          w.d(
            (u.text != null ? 1 : 0) |
                (u.color != null ? 2 : 0) |
                (u.properties != null ? 4 : 0),
          );
          if (u.text != null) w.str(u.text!);
          if (u.color != null) {
            w.b(u.color! >> 16);
            w.b(u.color! >> 8);
            w.b(u.color!);
            w.b(u.color! >> 24);
          }
          if (u.properties != null) w.bytes(u.properties!);
        });
  static Uint8List encode(SpriteDocument doc, {bool compressed = true}) {
    require(
      doc.frames.isNotEmpty && doc.layers.isNotEmpty,
      'Document must have a frame and layer',
    );
    final uuid = doc.layers.any((l) => l.uuid != null);
    final frames = <Uint8List>[];
    for (var fi = 0; fi < doc.frames.length; fi++) {
      final f = doc.frames[fi], chunks = <Uint8List>[];
      void addUser(UserData? u) {
        final b = _user(u);
        if (b != null) chunks.add(b);
      }

      void palette(List<int> pal) {
        chunks.add(
          _chunk(0x2019, (w) {
            w.d(pal.length);
            w.d(0);
            w.d(pal.length - 1);
            w.zeros(8);
            for (var index = 0; index < pal.length; index++) {
              final c = pal[index];
              final name = f.paletteNames[index];
              w.w(name == null ? 0 : 1);
              w.b(c >> 16);
              w.b(c >> 8);
              w.b(c);
              w.b(c >> 24);
              if (name != null) w.str(name);
            }
          }),
        );
      }

      if (fi == 0) {
        for (final l in doc.layers) {
          chunks.add(
            _chunk(0x2004, (w) {
              w.w((l.flags & ~1) | (l.visible ? 1 : 0));
              w.w(0);
              w.w(0);
              w.w(0);
              w.w(0);
              w.w(0);
              w.b(l.opacity);
              w.zeros(3);
              w.str(l.name);
              if (uuid) w.bytes(l.uuid ?? Uint8List(16));
            }),
          );
          addUser(l.data);
        }
      }
      final pc = f.metadata
          .where((c) => [4, 17, 0x2019].contains(c.type))
          .toList();
      for (final c in f.metadata.where((c) => c.type == 0x2007)) {
        chunks.add(_chunk(c.type, (w) => w.bytes(c.bytes)));
      }
      if (fi == 0) palette(f.palette);
      for (final c in pc) {
        chunks.add(_chunk(c.type, (w) => w.bytes(c.bytes)));
      }
      // Effective palettes must not depend on deleted/reordered frames.
      // Include names so this normalization does not erase palette metadata.
      palette(f.palette);
      for (final entry in f.palettePatches.entries) {
        chunks.add(
          _chunk(0x2019, (w) {
            w.d(f.palette.length);
            w.d(entry.key);
            w.d(entry.key);
            w.zeros(8);
            w.w(0);
            w.b(entry.value >> 16);
            w.b(entry.value >> 8);
            w.b(entry.value);
            w.b(entry.value >> 24);
          }),
        );
      }
      if (fi == 0) addUser(doc.data);
      if (fi == 0 && doc.tags.isNotEmpty) {
        chunks.add(
          _chunk(0x2018, (w) {
            w.w(doc.tags.length);
            w.zeros(8);
            for (final t in doc.tags) {
              w.w(t.from);
              w.w(t.to);
              w.b(t.direction);
              w.w(t.repeat);
              w.zeros(6);
              w.bytes(t.color);
              w.b(0);
              w.str(t.name);
            }
          }),
        );
        if (doc.tags.any((t) => t.data != null)) {
          for (final t in doc.tags) {
            addUser(t.data ?? UserData());
          }
        }
      }
      for (var li = 0; li < f.cels.length; li++) {
        final c = f.cels[li];
        if (c == null) continue;
        chunks.add(
          _chunk(0x2005, (w) {
            w.w(li);
            w.w(c.x);
            w.w(c.y);
            w.b(c.opacity);
            w.w(c.link != null ? 1 : (compressed ? 2 : 0));
            w.w(0);
            w.zeros(5);
            if (c.link != null) {
              w.w(c.link!);
            } else {
              w.w(c.width);
              w.w(c.height);
              final raw = _Writer();
              for (final v in c.pixels) {
                if (doc.depth == 8) {
                  raw.b(v);
                } else if (doc.depth == 16) {
                  raw.b(v);
                  raw.b(v >> 24);
                } else {
                  raw.b(v >> 16);
                  raw.b(v >> 8);
                  raw.b(v);
                  raw.b(v >> 24);
                }
              }
              final data = raw.result();
              w.bytes(compressed ? ZLibEncoder().convert(data) : data);
            }
          }),
        );
        addUser(c.data);
      }
      final fw = _Writer();
      fw.d(16 + chunks.fold<int>(0, (n, c) => n + c.length));
      fw.w(0xf1fa);
      fw.w(chunks.length.clamp(0, 65535));
      fw.w(f.duration);
      fw.zeros(2);
      fw.d(chunks.length);
      for (final c in chunks) {
        fw.bytes(c);
      }
      frames.add(fw.result());
    }
    final header = doc.header == null
        ? Uint8List(128)
        : Uint8List.fromList(doc.header!);
    if (doc.header == null) {
      header[34] = 1;
      header[35] = 1;
    }
    final b = ByteData.sublistView(header);
    b.setUint32(
      0,
      128 + frames.fold<int>(0, (n, f) => n + f.length),
      Endian.little,
    );
    b.setUint16(4, 0xa5e0, Endian.little);
    b.setUint16(6, doc.frames.length, Endian.little);
    b.setUint16(8, doc.width, Endian.little);
    b.setUint16(10, doc.height, Endian.little);
    b.setUint16(12, doc.depth, Endian.little);
    b.setUint32(14, 1 | (uuid ? 4 : 0), Endian.little);
    b.setUint16(18, doc.frames.first.duration, Endian.little);
    header[28] = doc.transparentIndex;
    final result = BytesBuilder(copy: false)..add(header);
    for (final f in frames) {
      result.add(f);
    }
    final bytes = result.toBytes();
    require(bytes.length <= maxFile, 'Saved document exceeds 64 MiB');
    return bytes;
  }
}

class _LimitedSink implements Sink<List<int>> {
  final int limit;
  final void Function(List<int>) output;
  int count = 0;
  _LimitedSink(this.limit, this.output);
  @override
  void add(List<int> data) {
    count += data.length;
    require(count <= limit, 'Inflated cel exceeds declared size');
    output(data);
  }

  @override
  void close() {}
}
