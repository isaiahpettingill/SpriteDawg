import 'dart:io';

import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/document.dart';

void main() {
  final output = Directory('/tmp/spritedawg-dart-interop')..createSync();
  final root = Directory('app/src/test/resources/upstream');
  for (final f in root.listSync().whereType<File>()) {
    try {
      final d = AsepriteCodec.decode(f.readAsBytesSync()),
          name = f.uri.pathSegments.last;
      File('${output.path}/$name').writeAsBytesSync(AsepriteCodec.encode(d));
      for (var i = 0; i < d.frames.length; i++) {
        File(
          '${output.path}/$name.$i.rgba',
        ).writeAsBytesSync(rgbaBytes(d.composite(i)));
      }
    } on FormatException {
      // Unsupported fixtures are deliberately refused by the editor.
    }
  }
}
