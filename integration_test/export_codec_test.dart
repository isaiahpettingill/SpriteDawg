// Disposable emulator only. Pure in-memory encode/decode; no user files/pickers.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_avif_platform_interface/flutter_avif_platform_interface.dart'
    as avif;
import 'package:spritedawg/export/image_export.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'registered Android AVIF encoder retains dimensions and bounded alpha',
    (tester) async {
      final rgba = Uint8List.fromList([
        for (var i = 0; i < 16 * 16; i++) ...[
          120,
          80,
          40,
          [0, 64, 128, 255][i % 4],
        ],
      ]);
      final bytes = await encodeImageExport(
        ImageExportPayload(
          width: 16,
          height: 16,
          rgbaFrames: [rgba],
          durationMs: [100],
        ),
        ImageExportFormat.avif,
      ).timeout(const Duration(seconds: 60));
      expect(bytes.length, greaterThan(32));
      final decoded = await avif.FlutterAvifPlatform.api
          .decodeSingleFrameImage(avifBytes: bytes)
          .timeout(const Duration(seconds: 30));
      expect(decoded.width, 16);
      expect(decoded.height, 16);
      for (var i = 3; i < rgba.length; i += 4) {
        expect((decoded.data[i] - rgba[i]).abs(), lessThanOrEqualTo(2));
      }
    },
  );
}
