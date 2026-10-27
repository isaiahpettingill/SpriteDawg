import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/palette_presets.dart';

int _rgb(int red, int green, int blue) =>
    0xff000000 | (red << 16) | (green << 8) | blue;

PalettePreset _preset(String id) =>
    palettePresets.singleWhere((preset) => preset.id == id);

void main() {
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
          preset.colors.every(
            (color) => color >= 0xff000000 && color <= 0xffffffff,
          ),
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
}
