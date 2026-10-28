// Visual QA from the production Dart editor; no mock rendering or imagegen.
// Run: dart tool/new_brush_preview.dart [output.png]
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:spritedawg/engine/editor_engine.dart';

void main(List<String> args) {
  const size = 160, header = 18;
  final sheet = img.Image(width: size * 3, height: (size + header) * 2);
  img.fill(sheet, color: img.ColorRgb8(24, 28, 32));
  const green = [0xff172f28, 0xff28523b, 0xff49794b, 0xff7fab5d, 0xffb5d979];
  const autumn = [0xff412b25, 0xff714131, 0xffa96439, 0xffd79650, 0xffefd17c];
  const labels = [
    'LEAVES / 32 PX',
    'LEAVES / 16 PX',
    'AUTUMN PALETTE',
    'SPLATTER / RGB',
    'RGB OVER BLUE',
    'INDEXED / EXACT',
  ];
  for (var panel = 0; panel < labels.length; panel++) {
    final e = EditorEngine();
    e.invoke('new', {'width': size, 'height': size});
    final palette = panel == 2 ? autumn : green;
    e.document.frames[0].palette = [0, ...palette];
    final points = <List<int>>[];
    if (panel < 3) {
      if (panel == 1) {
        points.addAll([
          [24, 20], [24, 120], [64, 120], [96, 40], [136, 40], [136, 140],
        ]);
      } else {
        for (var y = 0; y <= size; y += 20) {
          points.addAll(y % 40 == 0 ? [[0, y], [159, y]] : [[159, y], [0, y]]);
        }
      }
      e.stroke({
        'tool': 'leaves', 'points': points, 'size': panel == 1 ? 16 : 32,
        'seed': 421, 'color': palette[2], 'paletteIndex': 3,
      });
    } else {
      if (panel == 4) {
        e.document.editable(0, 0).pixels.fillRange(0, size * size, 0xff173b64);
      }
      if (panel == 5) {
        e.document.depth = 8;
        e.document.frames[0].palette = [0, 0xc0ee72b3, 0xc0ee72b3];
      }
      for (var burst = 0; burst < 3; burst++) {
        e.stroke({
          'tool': 'splatter',
          'points': [[32 + burst * 48, 35]],
          'size': 32, 'seed': 421 + burst, 'color': 0xc0ee72b3,
          if (panel == 5) 'paletteIndex': 2,
        });
      }
      e.stroke({
        'tool': 'splatter',
        'points': [[20, 112], [64, 76], [140, 126]],
        'size': 32, 'seed': 424, 'color': 0xc0ee72b3,
        if (panel == 5) 'paletteIndex': 2,
      });
    }
    final pixels = e.document.composite(0);
    final left = panel % 3 * size, top = panel ~/ 3 * (size + header);
    img.drawString(sheet, labels[panel], font: img.arial14,
        x: left + 5, y: top + 2, color: img.ColorRgb8(232, 238, 240));
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final p = pixels[y * size + x], alpha = p >> 24 & 255;
        final background = (x ~/ 8 + y ~/ 8).isEven ? 40 : 52;
        int blend(int shift) =>
            (((p >> shift & 255) * alpha + background * (255 - alpha)) + 127) ~/ 255;
        sheet.setPixelRgb(left + x, top + header + y, blend(16), blend(8), blend(0));
      }
    }
  }
  final output = File(args.isEmpty ? 'build/new-brush-preview.png' : args[0]);
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(img.encodePng(img.copyResize(sheet, width: sheet.width * 3,
      interpolation: img.Interpolation.nearest)));
  stdout.writeln(output.path);
}
