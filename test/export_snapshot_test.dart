import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/export/export_snapshot.dart';
import 'package:spritedawg/export/spritesheet.dart';

SpriteDocument fixture() => SpriteDocument(
  1,
  1,
  [Layer('visible'), Layer('hidden', visible: false)],
  [
    for (var i = 0; i < 4; i++)
      Frame(
        duration: 50 + i * 25,
        cels: [
          Cel(0, 0, 1, 1, Uint32List.fromList([0xff000000 | (i + 1) << 16])),
          Cel(0, 0, 1, 1, Uint32List.fromList([0xffffffff])),
        ],
      ),
  ],
  tags: [Tag(1, 3, 'walk', direction: 2, repeat: 3)],
);

void main() {
  test('snapshot composites visible layers and does not share pixels', () {
    final doc = fixture();
    final shot = exportSnapshot(doc, 2, {});
    expect(shot['indices'], [2]);
    final pixels = (shot['frames'] as List).single as Uint8List;
    expect(pixels, [3, 0, 0, 255]);
    pixels[0] = 99;
    expect(doc.frames[2].cels[0]!.pixels.single, 0xff030000);
  });
  test('tag playback honors directions, timing and endpoint handling', () {
    final doc = fixture();
    for (final entry in <int, List<int>>{
      0: [1, 2, 3],
      1: [3, 2, 1],
      2: [1, 2, 3, 2],
      3: [3, 2, 1, 2],
    }.entries) {
      doc.tags.single.direction = entry.key;
      final shot = exportSnapshot(doc, 0, {
        'scope': 'tag',
        'tag': 0,
        'animation': true,
      });
      expect(shot['indices'], entry.value);
      expect(shot['durations'], entry.value.map((i) => 50 + i * 25).toList());
      expect(shot['repeat'], 3);
    }
    doc.tags.single.to = 2;
    expect(
      exportSnapshot(doc, 0, {
        'scope': 'tag',
        'tag': 0,
        'animation': true,
      })['indices'],
      [2, 1],
    );
  });
  test('sheet tags stay chronological and are rebased to selected frames', () {
    final shot = exportSnapshot(fixture(), 0, {'scope': 'tag', 'tag': 0});
    expect(shot['indices'], [1, 2, 3]);
    final files = encodeSpritesheet(shot, name: 'walk', columns: 2, padding: 1);
    final json = jsonDecode(utf8.decode(files['walk.json']!)) as Map;
    final frames = json['frames'] as List;
    expect(frames.map((f) => f['duration']).toList(), [75, 100, 125]);
    expect(frames[2]['frame'], {'x': 1, 'y': 3, 'w': 1, 'h': 1});
    expect(json['meta']['image'], 'walk.png');
    expect(json['meta']['frameTags'][0], {
      'name': 'walk',
      'from': 0,
      'to': 2,
      'direction': 'pingpong',
      'repeat': 3,
    });
    final image = img.decodePng(files['walk.png']!)!;
    expect([image.width, image.height], [5, 5]);
    expect(image.getPixel(1, 1).r, 2);
    expect(image.getPixel(3, 1).r, 3);
    expect(image.getPixel(1, 3).r, 4);
    expect(image.getPixel(3, 3).a, 0);
    expect(image.getPixel(0, 0).a, 0);
  });
  test(
    'invalid selections, names and excessive exports fail before allocation',
    () {
      final doc = fixture();
      expect(
        () => exportSnapshot(doc, 0, {'scope': 'tag', 'tag': 4}),
        throwsFormatException,
      );
      expect(
        () => encodeSpritesheet(exportSnapshot(doc, 0, {}), name: '../escape'),
        throwsFormatException,
      );
      doc.width = 2048;
      doc.height = 2048;
      expect(
        () => exportSnapshot(doc, 0, {'scope': 'all'}),
        throwsFormatException,
      );
    },
  );
}
