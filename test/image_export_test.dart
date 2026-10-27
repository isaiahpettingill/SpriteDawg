import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:spritedawg/export/image_export.dart';

ImageExportPayload fixture({bool animated = true}) => ImageExportPayload(
  width: 2,
  height: 1,
  rgbaFrames: [
    Uint8List.fromList([255, 0, 0, 255, 23, 45, 67, 128]),
    if (animated) Uint8List.fromList([0, 0, 255, 255, 0, 0, 0, 0]),
  ],
  durationMs: animated ? [100, 230] : [100],
);

void main() {
  for (final format in [ImageExportFormat.apng, ImageExportFormat.webp]) {
    test('$format preserves frame pixels, timing and alpha', () {
      final payload = fixture();
      final bytes = encodeImageExportSync(payload, format);
      final decoded = img.decodeImage(bytes)!;
      expect(decoded.numFrames, 2);
      expect(decoded.width, 2);
      expect(decoded.height, 1);
      for (var i = 0; i < 2; i++) {
        expect(decoded.frames[i].frameDuration, payload.durationMs[i]);
        expect(
          decoded.frames[i].getBytes(order: img.ChannelOrder.rgba),
          payload.rgbaFrames[i],
        );
      }
    });
  }
  test('GIF has GIF89a signature, frames, timing and binary transparency', () {
    final bytes = encodeImageExportSync(fixture(), ImageExportFormat.gif);
    expect(String.fromCharCodes(bytes.take(6)), 'GIF89a');
    final decoded = img.decodeGif(bytes)!;
    expect(decoded.numFrames, 2);
    expect(decoded.frames.map((f) => f.frameDuration), [100, 230]);
    expect(decoded.frames[0].getPixel(0, 0).a, 255);
    expect(decoded.frames[1].getPixel(1, 0).a, 0);
  });
  test(
    'GIF loop count means total plays; one play omits Netscape extension',
    () {
      for (final total in [0, 1, 2, 7]) {
        final f = fixture();
        final p = ImageExportPayload(
          width: f.width,
          height: f.height,
          rgbaFrames: f.rgbaFrames,
          durationMs: f.durationMs,
          loopCount: total,
        );
        final bytes = encodeImageExportSync(p, ImageExportFormat.gif);
        if (total == 1) {
          expect(bytes.sublist(13, 15), [0x21, 0xf9]);
        } else {
          expect(String.fromCharCodes(bytes.sublist(16, 27)), 'NETSCAPE2.0');
          expect(
            ByteData.sublistView(bytes).getUint16(29, Endian.little),
            total == 0 ? 0 : total - 1,
          );
        }
        expect(img.decodeGif(bytes)!.numFrames, 2);
      }
    },
  );
  test(
    'GIF preserves all 256 opaque colors without unnecessary quantization',
    () {
      final rgba = Uint8List.fromList(
        List.generate(
          256,
          (i) => [i, 255 - i, (i * 13) % 256, 255],
        ).expand((p) => p).toList(),
      );
      final p = ImageExportPayload(
        width: 256,
        height: 1,
        rgbaFrames: [rgba],
        durationMs: [100],
      );
      final decoded = img.decodeGif(
        encodeImageExportSync(p, ImageExportFormat.gif),
      )!;
      expect(decoded.getBytes(order: img.ChannelOrder.rgba), rgba);
    },
  );
  test('GIF quantization reserves transparency beyond 255 colors', () {
    final rgba = Uint8List.fromList([
      ...List.generate(
        300,
        (i) => [i % 256, i ~/ 256, (i * 19) % 256, 255],
      ).expand((p) => p),
      100,
      120,
      140,
      0,
    ]);
    final p = ImageExportPayload(
      width: 301,
      height: 1,
      rgbaFrames: [rgba],
      durationMs: [100],
    );
    final decoded = img.decodeGif(
      encodeImageExportSync(p, ImageExportFormat.gif),
    )!;
    expect(decoded.getPixel(300, 0).a, 0);
    for (var x = 0; x < 300; x++) {
      expect(decoded.getPixel(x, 0).a, 255);
    }
  });
  test('QOI header and independent spec decoder preserve straight alpha', () {
    final payload = fixture(animated: false);
    final bytes = encodeImageExportSync(payload, ImageExportFormat.qoi);
    expect(String.fromCharCodes(bytes.take(4)), 'qoif');
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(4), 2);
    expect(header.getUint32(8), 1);
    expect(bytes.sublist(12, 14), [4, 0]);
    expect(_decodeQoi(bytes), payload.rgbaFrames.single);
  });
  test('QOI repeated pixels and index reuse round trip', () {
    final rgba = Uint8List.fromList([
      ...List.generate(70, (_) => [0, 0, 0, 255]).expand((x) => x),
      25,
      30,
      40,
      75,
      0,
      0,
      0,
      255,
      25,
      30,
      40,
      75,
    ]);
    final payload = ImageExportPayload(
      width: 73,
      height: 1,
      rgbaFrames: [rgba],
      durationMs: [100],
    );
    expect(
      _decodeQoi(encodeImageExportSync(payload, ImageExportFormat.qoi)),
      rgba,
    );
  });
  test(
    'still formats reject animation instead of silently dropping frames',
    () {
      for (final format in [ImageExportFormat.qoi, ImageExportFormat.avif]) {
        expect(() => fixture().validate(format), throwsFormatException);
      }
    },
  );
  test('validates byte lengths, duration and pre-allocation frame budget', () {
    final bad = ImageExportPayload(
      width: 2,
      height: 2,
      rgbaFrames: [Uint8List(1)],
      durationMs: [0],
    );
    expect(() => bad.validate(ImageExportFormat.gif), throwsFormatException);
    final large = ImageExportPayload(
      width: 8192,
      height: 8192,
      rgbaFrames: [Uint8List(0)],
      durationMs: [100],
    );
    expect(() => large.validate(ImageExportFormat.webp), throwsFormatException);
  });
}

// Independent format reader for tests, implementing every QOI v1 opcode.
Uint8List _decodeQoi(Uint8List bytes) {
  final header = ByteData.sublistView(bytes);
  final count = header.getUint32(4) * header.getUint32(8);
  final output = <int>[];
  final index = List.generate(64, (_) => [0, 0, 0, 0]);
  var pixel = [0, 0, 0, 255];
  var pos = 14;
  while (output.length < count * 4) {
    final op = bytes[pos++];
    var run = 1;
    if (op == 0xff) {
      pixel = bytes.sublist(pos, pos + 4);
      pos += 4;
    } else if (op == 0xfe) {
      pixel = [...bytes.sublist(pos, pos + 3), pixel[3]];
      pos += 3;
    } else {
      switch (op >> 6) {
        case 0:
          pixel = List.of(index[op & 63]);
        case 1:
          pixel = [
            (pixel[0] + ((op >> 4) & 3) - 2) & 255,
            (pixel[1] + ((op >> 2) & 3) - 2) & 255,
            (pixel[2] + (op & 3) - 2) & 255,
            pixel[3],
          ];
        case 2:
          final second = bytes[pos++];
          final dg = (op & 63) - 32;
          pixel = [
            (pixel[0] + dg + (second >> 4) - 8) & 255,
            (pixel[1] + dg) & 255,
            (pixel[2] + dg + (second & 15) - 8) & 255,
            pixel[3],
          ];
        case 3:
          run = (op & 63) + 1;
      }
    }
    index[(pixel[0] * 3 + pixel[1] * 5 + pixel[2] * 7 + pixel[3] * 11) % 64] =
        List.of(pixel);
    for (var n = 0; n < run; n++) {
      output.addAll(pixel);
    }
  }
  expect(bytes.sublist(pos), [0, 0, 0, 0, 0, 0, 0, 1]);
  return Uint8List.fromList(output);
}
