import 'dart:convert';

import 'document.dart';

/// Called only on the engine's transaction candidate; failures never commit.
void applyPaletteAction(
  SpriteDocument d,
  Map<String, dynamic> args,
  int frame,
) {
  int number(String key) {
    final n = args[key];
    require(n is int, '$key must be an integer');
    return n as int;
  }

  int color() {
    final c = number('color');
    require(c >= 0 && c <= 0xffffffff, 'Invalid RGBA color');
    return c;
  }

  String name() {
    final n = args['name'];
    require(
      n is String && utf8.encode(n).length <= 65535,
      'Invalid palette name',
    );
    return n as String;
  }

  void clean(Frame f) {
    f.metadata.removeWhere((c) => [4, 17, 0x2019].contains(c.type));
    f.palettePatches.clear();
  }

  void index(int i) => require(
    i >= 0 && i < d.frames[frame].palette.length,
    'Invalid palette index',
  );
  void uniform() => require(
    d.frames.every((f) => f.palette.length == d.frames[frame].palette.length),
    'Palette sizes differ between frames. Convert to RGBA and normalize palettes externally before rearranging.',
  );
  void reorder(List<int> order, List<int> mapping) {
    for (final f in d.frames) {
      final old = f.palette, names = Map<int, String>.of(f.paletteNames);
      f.palette = [for (final i in order) old[i]];
      f.paletteNames = {
        for (var i = 0; i < order.length; i++)
          if (names.containsKey(order[i])) i: names[order[i]]!,
      };
      if (d.depth == 8) {
        for (final c in f.cels) {
          if (c == null || c.link != null) continue;
          for (var p = 0; p < c.pixels.length; p++) {
            require(c.pixels[p] < mapping.length, 'Invalid pixel index');
            c.pixels[p] = mapping[c.pixels[p]];
          }
        }
      }
      clean(f);
    }
    if (d.depth == 8) d.transparentIndex = mapping[d.transparentIndex];
  }

  require(frame >= 0 && frame < d.frames.length, 'Invalid frame');
  switch (args['action']) {
    case 'palettePreset':
      final values = args['colors'];
      require(
        values is List && values.isNotEmpty && values.length <= 256,
        'A palette preset must contain 1–256 colors',
      );
      final colors = <int>[];
      for (final value in values as List) {
        require(
          value is int && value >= 0 && value <= 0xffffffff,
          'Invalid preset RGBA color',
        );
        colors.add(value as int);
      }
      final presetNames = <int, String>{};
      if (args.containsKey('names')) {
        final names = args['names'];
        require(
          names is List && names.length == colors.length,
          'Preset names must match the number of colors',
        );
        for (var i = 0; i < colors.length; i++) {
          final value = (names as List)[i];
          require(
            value is String && utf8.encode(value).length <= 65535,
            'Invalid preset palette name',
          );
          final name = value as String;
          if (name.isNotEmpty) presetNames[i] = name;
        }
      }
      require(
        !args.containsKey('remap') || args['remap'] is bool,
        'Remap must be a boolean',
      );
      if (d.depth == 8) {
        require(
          args['remap'] == true,
          'Confirm indexed color remapping before applying a preset',
        );
        require(
          colors.length < 256,
          'Indexed presets need a free transparency slot (255 colors maximum)',
        );
        // A linked cel can display different colors in different frames. Check
        // the expanded budget before copying, then resolve all links before any
        // source cel or palette is changed.
        var count = 0;
        for (var f = 0; f < d.frames.length; f++) {
          for (var l = 0; l < d.layers.length; l++) {
            count += d.resolved(f, l)?.pixels.length ?? 0;
            require(
              count <= 16777216,
              'Palette remapping would exceed decoded pixel budget',
            );
          }
        }
        final resolved = [
          for (var f = 0; f < d.frames.length; f++)
            [
              for (var l = 0; l < d.layers.length; l++)
                d.resolved(f, l)?.copy(),
            ],
        ];
        final transparent = colors.length;
        int nearest(int color) {
          if (color >> 24 == 0) return transparent;
          var best = 0, distance = 1 << 40;
          for (var i = 0; i < colors.length; i++) {
            var candidate = 0;
            for (final shift in [0, 8, 16, 24]) {
              final delta = (colors[i] >> shift & 255) - (color >> shift & 255);
              candidate += delta * delta;
            }
            if (candidate < distance) {
              best = i;
              distance = candidate;
            }
          }
          return best;
        }

        for (var f = 0; f < d.frames.length; f++) {
          // Quantize at most 256 palette values, not every decoded pixel.
          final mapping = d.frames[f].palette.map(nearest).toList();
          for (var l = 0; l < d.layers.length; l++) {
            final c = resolved[f][l];
            if (c != null) {
              for (var p = 0; p < c.pixels.length; p++) {
                final value = c.pixels[p];
                require(value < mapping.length, 'Invalid pixel index');
                // Background layers display the old transparent-index swatch
                // as a color; ordinary layers use it as a transparent hole.
                c.pixels[p] =
                    value == d.transparentIndex && d.layers[l].flags & 8 == 0
                    ? transparent
                    : mapping[value];
              }
              c.link = null;
            }
            d.frames[f].cels[l] = c;
          }
        }
        colors.add(0);
        d.transparentIndex = transparent;
      }
      for (final f in d.frames) {
        f.palette = List.of(colors);
        f.paletteNames = Map.of(presetNames);
        clean(f);
      }
      break;
    case 'paletteEdit':
      final i = number('index');
      index(i);
      final c = color(), n = name(), f = d.frames[frame];
      f.palette[i] = c;
      if (n.isEmpty) {
        f.paletteNames.remove(i);
      } else {
        f.paletteNames[i] = n;
      }
      clean(f);
      break;
    case 'paletteAdd':
      uniform();
      final c = color(), n = name();
      require(
        d.frames[frame].palette.length < 256,
        'Palette is full (256 entries)',
      );
      for (final f in d.frames) {
        final i = f.palette.length;
        f.palette.add(c);
        if (n.isNotEmpty) f.paletteNames[i] = n;
        clean(f);
      }
      break;
    case 'paletteMove':
      uniform();
      final i = number('index'), to = number('to');
      index(i);
      index(to);
      final order = List.generate(d.frames[frame].palette.length, (i) => i);
      order.insert(to, order.removeAt(i));
      final map = List.filled(order.length, 0);
      for (var j = 0; j < order.length; j++) {
        map[order[j]] = j;
      }
      reorder(order, map);
      break;
    case 'paletteRemove':
      uniform();
      final i = number('index'), replacement = number('replacement');
      index(i);
      index(replacement);
      require(
        i != replacement && d.frames[frame].palette.length > 1,
        'Choose another replacement swatch',
      );
      require(
        d.depth != 8 ||
            (i != d.transparentIndex && replacement != d.transparentIndex),
        'The transparent index cannot be removed or used as a replacement',
      );
      final order = List.generate(d.frames[frame].palette.length, (i) => i)
        ..remove(i);
      final map = List.generate(order.length + 1, (j) => j > i ? j - 1 : j);
      map[i] = map[replacement];
      reorder(order, map);
      break;
    case 'convertMode':
      final depth = number('depth');
      require(depth == 8 || depth == 32, 'Choose indexed or RGBA');
      if (depth == d.depth) return;
      // Resolve before changing depth/palettes. A linked cel may display differently
      // in each frame, so conversion intentionally materializes independent cels.
      var count = 0;
      for (var f = 0; f < d.frames.length; f++) {
        for (var l = 0; l < d.layers.length; l++) {
          count += d.resolved(f, l)?.pixels.length ?? 0;
        }
      }
      require(
        count <= 16777216,
        'Conversion would exceed decoded pixel budget',
      );
      final resolved = [
        for (var f = 0; f < d.frames.length; f++)
          [for (var l = 0; l < d.layers.length; l++) d.resolved(f, l)?.copy()],
      ];
      if (depth == 32) {
        for (var f = 0; f < d.frames.length; f++) {
          for (var l = 0; l < d.layers.length; l++) {
            final c = resolved[f][l];
            if (c != null) {
              for (var p = 0; p < c.pixels.length; p++) {
                c.pixels[p] = d.display(c.pixels[p], f, l);
              }
              c.link = null;
            }
            d.frames[f].cels[l] = c;
          }
        }
        d.depth = 32;
      } else {
        final maxCount = d.frames.fold<int>(
          0,
          (n, f) => n > f.palette.length ? n : f.palette.length,
        );
        require(
          maxCount < 256,
          'Indexed conversion needs a free transparency slot; remove an unused swatch first',
        );
        // Every frame retains its own palette entries/names; padding is new data.
        for (final f in d.frames) {
          while (f.palette.length <= maxCount) {
            f.palette.add(0);
          }
          clean(f);
        }
        d.transparentIndex = maxCount;
        d.depth = 8;
        for (var f = 0; f < d.frames.length; f++) {
          for (var l = 0; l < d.layers.length; l++) {
            final c = resolved[f][l];
            if (c != null) {
              for (var p = 0; p < c.pixels.length; p++) {
                c.pixels[p] = d.drawingColor(c.pixels[p], f);
              }
              c.link = null;
            }
            d.frames[f].cels[l] = c;
          }
        }
      }
      break;
    default:
      throw FormatException('Unknown palette action ${args['action']}');
  }
}
