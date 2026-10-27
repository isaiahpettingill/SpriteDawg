import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/palette_presets.dart';

int _rgb(int red, int green, int blue) =>
    0xff000000 | (red << 16) | (green << 8) | blue;

PalettePreset _preset(String id) =>
    palettePresets.singleWhere((preset) => preset.id == id);

void main() {
  test(
    'Original material ramps retain opaque highlights and alpha overlays',
    () {
      final p = _preset('spritedawg-materials');
      for (final material in [
        'Grass',
        'Stone',
        'Wood',
        'Fire',
        'Water',
        'Gold',
        'Silver',
        'Copper',
        'Bronze',
        'Steel',
        'Diamond',
        'Ruby',
        'Emerald',
        'Sapphire',
        'Amethyst',
      ]) {
        final start = p.colorNames.indexOf('$material deep shadow');
        expect(start, greaterThanOrEqualTo(0));
        expect(
          p.colors.sublist(start, start + 5).every((c) => c >> 24 == 255),
          isTrue,
        );
        expect(p.colors.sublist(start + 5, start + 8).map((c) => c >> 24), [
          64,
          128,
          192,
        ]);
        expect(p.colors[start + 2] & 0xffffff, p.colors[start + 6] & 0xffffff);
      }
      expect(p.colors[p.colorNames.indexOf('Gold glint')], 0xfffff4ba);
      expect(p.colors[p.colorNames.indexOf('Diamond glint')], 0xffffffff);
    },
  );
  test(
    'Original character and food palettes retain searchable coherent ramps',
    () {
      final characters = _preset('spritedawg-characters');
      final food = _preset('spritedawg-food');
      for (final family in [
        'Skin deep',
        'Skin brown',
        'Skin olive',
        'Skin rose',
        'Skin light',
        'Cloth red',
        'Cloth blue',
        'Cloth green',
        'Cloth violet',
        'Cloth gold',
        'Cloth neutral',
      ]) {
        expect(characters.colorNames, contains('$family overlay 50%'));
      }
      for (final family in [
        'Berry',
        'Citrus',
        'Apple',
        'Leafy vegetables',
        'Root vegetables',
        'Bread',
        'Meat',
        'Chocolate',
        'Cream sweets',
        'Grape sweets',
        'Drink tea',
        'Drink juice',
      ]) {
        expect(food.colorNames, contains('$family overlay 50%'));
      }
      for (final p in [characters, food]) {
        for (var i = 0; i < p.colors.length; i += 7) {
          expect(
            p.colors.sublist(i, i + 4).every((c) => c >> 24 == 255),
            isTrue,
          );
          expect(p.colors.sublist(i + 4, i + 7).map((c) => c >> 24), [
            64,
            128,
            192,
          ]);
        }
      }
      final game = _preset('spritedawg-game-64');
      expect(game.colors.toSet().length, 64);
      expect(game.colors.every((c) => c >> 24 == 255), isTrue);
      expect(game.description, contains('Not AAP-64'));
    },
  );
  test(
    'Catalog identities, sizes, credits and permission sources are stable',
    () {
      const counts = {
        'pico-8': 16,
        'game-boy-monochrome': 4,
        'cga': 16,
        'cga0': 4,
        'cga0-high': 4,
        'cga1': 4,
        'cga1-high': 4,
        'zx-spectrum': 16,
        'master-system': 64,
        'amstrad-cpc': 27,
        'teletext': 8,
        'grayscale-16': 16,
        'web-safe': 216,
        'solarized': 16,
        'monokai-pygments': 11,
        'catppuccin-latte': 26,
        'catppuccin-frappe': 26,
        'catppuccin-macchiato': 26,
        'catppuccin-mocha': 26,
        'tic-80-sweetie-16': 16,
        'dawnbringer-16': 16,
        'spritedawg-materials': 120,
        'spritedawg-game-64': 64,
        'spritedawg-characters': 77,
        'spritedawg-food': 84,
      };
      expect(palettePresets.map((p) => p.id).toList(), counts.keys.toList());
      for (final preset in palettePresets) {
        expect(preset.colors.length, counts[preset.id], reason: preset.id);
        expect(preset.colors.length, lessThan(256));
        expect(preset.name.trim(), isNotEmpty);
        expect(preset.description.trim(), isNotEmpty);
        expect(preset.credit.trim(), isNotEmpty);
        expect(preset.source.trim(), isNotEmpty);
        expect(
          preset.source.startsWith('https://') ||
              preset.source.startsWith('docs/PALETTE_SOURCES.md'),
          isTrue,
        );
        expect(preset.license.trim(), isNotEmpty);
        expect(
          preset.colorNames.isEmpty ||
              preset.colorNames.length == preset.colors.length,
          isTrue,
        );
        expect(
          preset.colors.every((color) => color >= 0 && color <= 0xffffffff),
          isTrue,
          reason: preset.id,
        );
      }
      expect(_preset('pico-8').license, 'CC0-1.0');
      expect(_preset('solarized').license, 'MIT');
      expect(_preset('game-boy-monochrome').description, contains('neutral'));
      expect(
        _preset('game-boy-monochrome').description,
        contains('not an original LCD'),
      );
    },
  );

  test('PICO-8 retains all 16 CC0 colors in the original slot order', () {
    expect(_preset('pico-8').colors, const [
      0xff000000,
      0xff1d2b53,
      0xff7e2553,
      0xff008751,
      0xffab5236,
      0xff5f574f,
      0xffc2c3c7,
      0xfffff1e8,
      0xffff004d,
      0xffffa300,
      0xffffec27,
      0xff00e436,
      0xff29adff,
      0xff83769c,
      0xffff77a8,
      0xffffccaa,
    ]);
  });

  test('Solarized retains the creator neutral-then-accent order', () {
    expect(_preset('solarized').colors, const [
      0xff002b36,
      0xff073642,
      0xff586e75,
      0xff657b83,
      0xff839496,
      0xff93a1a1,
      0xffeee8d5,
      0xfffdf6e3,
      0xffb58900,
      0xffcb4b16,
      0xffdc322f,
      0xffd33682,
      0xff6c71c4,
      0xff268bd2,
      0xff2aa198,
      0xff859900,
    ]);
  });

  test('CGA constants follow RGBI with brown correction and mode subsets', () {
    final expected = <int>[
      for (var index = 0; index < 16; index++)
        _rgb(
          ((index >> 2) & 1) * 170 + ((index >> 3) & 1) * 85,
          index == 6 ? 85 : ((index >> 1) & 1) * 170 + ((index >> 3) & 1) * 85,
          (index & 1) * 170 + ((index >> 3) & 1) * 85,
        ),
    ];
    expect(_preset('cga').colors, expected);
    const subsets = {
      'cga0': [0, 2, 4, 6],
      'cga0-high': [0, 10, 12, 14],
      'cga1': [0, 3, 5, 7],
      'cga1-high': [0, 11, 13, 15],
    };
    for (final entry in subsets.entries) {
      expect(
        _preset(entry.key).colors,
        entry.value.map((index) => expected[index]).toList(),
        reason: entry.key,
      );
    }
  });

  test('ZX Spectrum preserves both black slots and basic/bright order', () {
    final expected = <int>[
      for (final level in [192, 255])
        for (var index = 0; index < 8; index++)
          _rgb(
            ((index >> 1) & 1) * level,
            ((index >> 2) & 1) * level,
            (index & 1) * level,
          ),
    ];
    final colors = _preset('zx-spectrum').colors;
    expect(colors, expected);
    expect(colors[0], colors[8]);
    expect(colors.toSet().length, 15);
  });

  test('Master System enumerates the complete 00BBGGRR color space', () {
    expect(_preset('master-system').colors, [
      for (var index = 0; index < 64; index++)
        _rgb(
          (index & 3) * 85,
          ((index >> 2) & 3) * 85,
          ((index >> 4) & 3) * 85,
        ),
    ]);
    expect(_preset('master-system').colors.toSet().length, 64);
  });

  test('Amstrad CPC uses BASIC ink order with blue changing fastest', () {
    const levels = [0, 128, 255];
    expect(_preset('amstrad-cpc').colors, [
      for (final green in levels)
        for (final red in levels)
          for (final blue in levels) _rgb(red, green, blue),
    ]);
  });

  test('Teletext is the documented blue-first one-bit RGB cube', () {
    expect(_preset('teletext').colors, [
      for (final green in [0, 255])
        for (final red in [0, 255])
          for (final blue in [0, 255]) _rgb(red, green, blue),
    ]);
  });

  test('Game Boy Monochrome is neutral, white to black, not green LCD', () {
    expect(_preset('game-boy-monochrome').colors, [
      for (final shade in [255, 170, 85, 0]) _rgb(shade, shade, shade),
    ]);
  });

  test('Grayscale and Web Safe contain their full documented numeric sets', () {
    expect(_preset('grayscale-16').colors, [
      for (var index = 0; index < 16; index++)
        _rgb(index * 17, index * 17, index * 17),
    ]);
    const levels = [255, 204, 153, 102, 51, 0];
    expect(_preset('web-safe').colors, [
      for (final red in levels)
        for (final green in levels)
          for (final blue in levels) _rgb(red, green, blue),
    ]);
    expect(_preset('web-safe').colors.toSet().length, 216);
  });

  test('The catalog and every nested color list reject mutation', () {
    expect(
      () => palettePresets.add(palettePresets.first),
      throwsUnsupportedError,
    );
    expect(
      () => palettePresets[0] = palettePresets.last,
      throwsUnsupportedError,
    );
    for (final preset in palettePresets) {
      expect(() => preset.colors.add(0xff123456), throwsUnsupportedError);
      expect(() => preset.colorNames.add('Changed'), throwsUnsupportedError);
      expect(() => preset.colors[0] = 0xff123456, throwsUnsupportedError);
    }
  });

  test('The bundled Solarized notice exactly retains the full MIT notice', () {
    final notice = File('LICENSES/Solarized-MIT.txt').readAsStringSync();
    expect(solarizedPaletteLicense, notice);
    expect(notice, startsWith('Copyright (c) 2011 Ethan Schoonover'));
    expect(notice, contains('The above copyright notice'));
    expect(notice, contains('THE SOFTWARE IS PROVIDED "AS IS"'));
    final cc0 = File('LICENSES/CC0-1.0.txt').readAsStringSync();
    expect(cc0, contains('CC0 1.0 Universal'));
    expect(cc0, contains('3. Public License Fallback.'));
    expect(cc0, contains('4. Limitations and Disclaimers.'));
  });

  test('monokai-pygments preserves documented source order', () {
    expect(_preset('monokai-pygments').colors, const [
      0xff272822,
      0xff49483e,
      0xfff8f8f2,
      0xffed007e,
      0xff1e0010,
      0xff959077,
      0xff66d9ef,
      0xffff4689,
      0xffa6e22e,
      0xffae81ff,
      0xffe6db74,
    ]);
  });

  test('catppuccin-latte preserves documented source order', () {
    expect(_preset('catppuccin-latte').colors, const [
      0xffdc8a78,
      0xffdd7878,
      0xffea76cb,
      0xff8839ef,
      0xffd20f39,
      0xffe64553,
      0xfffe640b,
      0xffdf8e1d,
      0xff40a02b,
      0xff179299,
      0xff04a5e5,
      0xff209fb5,
      0xff1e66f5,
      0xff7287fd,
      0xff4c4f69,
      0xff5c5f77,
      0xff6c6f85,
      0xff7c7f93,
      0xff8c8fa1,
      0xff9ca0b0,
      0xffacb0be,
      0xffbcc0cc,
      0xffccd0da,
      0xffeff1f5,
      0xffe6e9ef,
      0xffdce0e8,
    ]);
  });

  test('catppuccin-frappe preserves documented source order', () {
    expect(_preset('catppuccin-frappe').colors, const [
      0xfff2d5cf,
      0xffeebebe,
      0xfff4b8e4,
      0xffca9ee6,
      0xffe78284,
      0xffea999c,
      0xffef9f76,
      0xffe5c890,
      0xffa6d189,
      0xff81c8be,
      0xff99d1db,
      0xff85c1dc,
      0xff8caaee,
      0xffbabbf1,
      0xffc6d0f5,
      0xffb5bfe2,
      0xffa5adce,
      0xff949cbb,
      0xff838ba7,
      0xff737994,
      0xff626880,
      0xff51576d,
      0xff414559,
      0xff303446,
      0xff292c3c,
      0xff232634,
    ]);
  });

  test('catppuccin-macchiato preserves documented source order', () {
    expect(_preset('catppuccin-macchiato').colors, const [
      0xfff4dbd6,
      0xfff0c6c6,
      0xfff5bde6,
      0xffc6a0f6,
      0xffed8796,
      0xffee99a0,
      0xfff5a97f,
      0xffeed49f,
      0xffa6da95,
      0xff8bd5ca,
      0xff91d7e3,
      0xff7dc4e4,
      0xff8aadf4,
      0xffb7bdf8,
      0xffcad3f5,
      0xffb8c0e0,
      0xffa5adcb,
      0xff939ab7,
      0xff8087a2,
      0xff6e738d,
      0xff5b6078,
      0xff494d64,
      0xff363a4f,
      0xff24273a,
      0xff1e2030,
      0xff181926,
    ]);
  });

  test('catppuccin-mocha preserves documented source order', () {
    expect(_preset('catppuccin-mocha').colors, const [
      0xfff5e0dc,
      0xfff2cdcd,
      0xfff5c2e7,
      0xffcba6f7,
      0xfff38ba8,
      0xffeba0ac,
      0xfffab387,
      0xfff9e2af,
      0xffa6e3a1,
      0xff94e2d5,
      0xff89dceb,
      0xff74c7ec,
      0xff89b4fa,
      0xffb4befe,
      0xffcdd6f4,
      0xffbac2de,
      0xffa6adc8,
      0xff9399b2,
      0xff7f849c,
      0xff6c7086,
      0xff585b70,
      0xff45475a,
      0xff313244,
      0xff1e1e2e,
      0xff181825,
      0xff11111b,
    ]);
  });

  // Independently transcribed from the official TIC-80 wiki color table.
  // Do not extract the first 000: block: config.js starts with sprite data.
  test('tic-80-sweetie-16 preserves documented source order', () {
    expect(_preset('tic-80-sweetie-16').colors, const [
      0xff1a1c2c,
      0xff5d275d,
      0xffb13e53,
      0xffef7d57,
      0xffffcd75,
      0xffa7f070,
      0xff38b764,
      0xff257179,
      0xff29366f,
      0xff3b5dc9,
      0xff41a6f6,
      0xff73eff7,
      0xfff4f4f4,
      0xff94b0c2,
      0xff566c86,
      0xff333c57,
    ]);
  });

  test('dawnbringer-16 preserves documented source order', () {
    expect(_preset('dawnbringer-16').colors, const [
      0xff140c1c,
      0xff442434,
      0xff30346d,
      0xff4e4a4e,
      0xff854c30,
      0xff346524,
      0xffd04648,
      0xff757161,
      0xff597dce,
      0xffd27d2c,
      0xff8595a1,
      0xff6daa2c,
      0xffd2aa99,
      0xff6dc2ca,
      0xffdad45e,
      0xffdeeed6,
    ]);
  });

  test('Named palette license notices match their distributed copies', () {
    expect(
      catppuccinPaletteLicense,
      File('LICENSES/Catppuccin-MIT.txt').readAsStringSync(),
    );
    expect(
      pygmentsPaletteLicense,
      File('LICENSES/Pygments-BSD-2-Clause.txt').readAsStringSync(),
    );
    expect(
      tic80PaletteLicense,
      File('LICENSES/TIC-80-MIT.txt').readAsStringSync(),
    );
    expect(
      dawnBringerPaletteLicense,
      File('LICENSES/DawnBringer-Free-Use.txt').readAsStringSync(),
    );
    expect(_preset('monokai-pygments').name, contains('Pygments'));
    expect(_preset('monokai-pygments').description, contains('not Pro'));
    expect(_preset('tic-80-sweetie-16').credit, contains('GrafxKid'));
    expect(_preset('catppuccin-mocha').colorNames.first, 'Rosewater');
    expect(_preset('catppuccin-mocha').colorNames.last, 'Crust');
  });
}
