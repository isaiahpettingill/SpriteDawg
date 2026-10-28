// Reproducible visual QA: production engine output, not a mock or AI image.
// Run: dart tool/bark_preview.dart [output.png]
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:spritedawg/engine/editor_engine.dart';

void main(List<String> args) {
  const width = 480, height = 160, scale = 3;
  final rgba = Uint8List(width * height * 4);
  const palettes = [
    [0xff34251b, 0xff593f2b, 0xff896343, 0xffb18a5c, 0xffd2ac78],
    [0xff34251b, 0xff593f2b, 0xff896343, 0xffb18a5c, 0xffd2ac78],
    [0xff1b3431, 0xff2b5953, 0xff43897f, 0xff5cb1a5, 0xff78d2c5],
  ];
  for (var panel = 0; panel < 3; panel++) {
    final e = EditorEngine();
    e.invoke('new', {'width': 160, 'height': 160});
    e.document.frames[0].palette = palettes[panel];
    final points = <List<int>>[];
    if (panel == 1) {
      points.addAll([
        [24, 20],
        [24, 120],
        [64, 120],
        [96, 40],
        [136, 40],
        [136, 140],
      ]);
    } else {
      for (var y = 0; y <= 160; y += 20) {
        points.addAll(y % 40 == 0 ? [[0, y], [159, y]] : [[159, y], [0, y]]);
      }
    }
    e.stroke({
      'tool': 'bark',
      'points': points,
      'size': panel == 1 ? 12 : 32,
      'seed': 421,
      'color': palettes[panel][2],
      'paletteIndex': 2,
    });
    final pixels = e.document.composite(0);
    for (var y = 0; y < 160; y++) {
      for (var x = 0; x < 160; x++) {
        final p = pixels[y * 160 + x];
        final i = (y * width + panel * 160 + x) * 4;
        final background = (x ~/ 8 + y ~/ 8).isEven ? 32 : 40;
        rgba[i] = p == 0 ? background : (p >> 16) & 255;
        rgba[i + 1] = p == 0 ? background : (p >> 8) & 255;
        rgba[i + 2] = p == 0 ? background : p & 255;
        rgba[i + 3] = 255;
      }
    }
  }
  final source = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
  );
  final output = File(args.isEmpty ? 'build/bark-preview.png' : args[0]);
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(
    img.encodePng(
      img.copyResize(source, width: width * scale, height: height * scale),
    ),
  );
  stdout.writeln(
    'Bark: 32 px brown patch | 12 px continuous stroke | teal palette',
  );
  stdout.writeln(output.path);
}
