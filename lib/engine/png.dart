import 'package:archive/archive.dart';
import 'dart:typed_data';

import 'document.dart' show maxPixels;

/// Encodes straight-alpha bytes as a non-interlaced, 8-bit RGBA PNG.
///
/// Export bypasses rendering surfaces, whose premultiplication can irreversibly
/// round low-alpha colors. Filter zero keeps the original sample bytes exact.
Uint8List encodeRgbaPng(
  Uint8List rgba, {
  required int width,
  required int height,
}) {
  if (width < 1 ||
      height < 1 ||
      width > 65535 ||
      height > 65535 ||
      width * height > maxPixels ||
      rgba.length != width * height * 4) {
    throw const FormatException('Invalid PNG dimensions or RGBA byte length');
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  final stride = width * 4;
  final rows = Uint8List(height * (stride + 1));
  for (var y = 0; y < height; y++) {
    final start = y * (stride + 1) + 1;
    rows.setRange(start, start + stride, rgba, y * stride);
  }
  final output = BytesBuilder(copy: false)
    ..add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> payload) {
    final name = type.codeUnits;
    var crc = 0xffffffff;
    for (final byte in name) {
      crc = _crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
    }
    for (final byte in payload) {
      crc = _crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
    }
    output
      ..add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List())
      ..add(name)
      ..add(payload)
      ..add((ByteData(4)..setUint32(0, crc ^ 0xffffffff)).buffer.asUint8List());
  }

  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().encode(rows, level: 6));
  chunk('IEND', const []);
  return output.takeBytes();
}

final _crcTable = List<int>.generate(256, (value) {
  var crc = value;
  for (var bit = 0; bit < 8; bit++) {
    crc = crc & 1 != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  }
  return crc;
}, growable: false);
