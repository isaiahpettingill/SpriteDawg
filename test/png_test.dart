import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/png.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pixels = Uint8List.fromList([
    for (final alpha in [0, 1, 17, 128, 254, 255]) ...[200, 100, 50, alpha],
  ]);
  test('PNG preserves all RGBA8 samples and emits valid independent CRCs', () {
    final png = encodeRgbaPng(pixels, width: 3, height: 2);
    final bytes = ByteData.sublistView(png);
    expect(bytes.getUint32(16), 3);
    expect(bytes.getUint32(20), 2);
    expect(png[24], 8);
    expect(png[25], 6);
    final compressed = BytesBuilder();
    var offset = 8;
    while (offset < png.length) {
      final length = bytes.getUint32(offset);
      final type = String.fromCharCodes(png.sublist(offset + 4, offset + 8));
      // Independent bit-at-a-time reference, not the encoder's CRC table.
      var crc = 0xffffffff;
      for (final byte in png.sublist(offset + 4, offset + 8 + length)) {
        crc ^= byte;
        for (var bit = 0; bit < 8; bit++) {
          crc = crc & 1 == 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
        }
      }
      expect(
        bytes.getUint32(offset + 8 + length),
        crc ^ 0xffffffff,
        reason: type,
      );
      if (type == 'IDAT') {
        compressed.add(png.sublist(offset + 8, offset + 8 + length));
      }
      offset += length + 12;
    }
    expect(offset, png.length);
    final rows = ZLibDecoder().convert(compressed.takeBytes());
    expect(rows, [0, ...pixels.take(12), 0, ...pixels.skip(12)]);
  });
  test('Independent Flutter PNG decoder accepts exported image', () async {
    final png = encodeRgbaPng(pixels, width: 3, height: 2);
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, 3);
    expect(image.height, 2);
    final decoded = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!.buffer.asUint8List();
    expect(
      [for (var i = 3; i < decoded.length; i += 4) decoded[i]],
      [0, 1, 17, 128, 254, 255],
    );
    expect(decoded.skip(20), [200, 100, 50, 255]);
    image.dispose();
    codec.dispose();
  });
  test('PNG rejects malformed or oversized allocations before encoding', () {
    for (final d in [(0, 1), (1, 0), (-1, 1), (65536, 1), (2049, 2048)]) {
      expect(
        () => encodeRgbaPng(Uint8List(4), width: d.$1, height: d.$2),
        throwsFormatException,
      );
    }
    expect(
      () => encodeRgbaPng(Uint8List(3), width: 1, height: 1),
      throwsFormatException,
    );
  });
}
