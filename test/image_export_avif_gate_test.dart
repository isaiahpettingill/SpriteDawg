import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_avif_platform_interface/flutter_avif_platform_interface.dart'
    as avif;
import 'package:spritedawg/export/image_export.dart';

class _PendingAvif implements avif.FlutterAvif {
  var pending = Completer<Uint8List>();
  var calls = 0;
  @override
  Future<Uint8List> encodeAvif({
    required int width,
    required int height,
    required int speed,
    required int maxThreads,
    required int timescale,
    required int maxQuantizer,
    required int minQuantizer,
    required int maxQuantizerAlpha,
    required int minQuantizerAlpha,
    required List<avif.EncodeFrame> imageSequence,
    required Uint8List exifData,
  }) {
    calls++;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final encoder = _PendingAvif();
  avif.FlutterAvifPlatform.api = encoder;
  final payload = ImageExportPayload(
    width: 16,
    height: 16,
    rgbaFrames: [Uint8List(16 * 16 * 4)],
    durationMs: [100],
  );
  test(
    'AVIF gate rejects overlapping work and releases after completion/error',
    () async {
      final first = encodeImageExport(payload, ImageExportFormat.avif);
      await expectLater(
        encodeImageExport(payload, ImageExportFormat.avif),
        throwsStateError,
      );
      expect(encoder.calls, 1);
      encoder.pending.complete(Uint8List.fromList([1]));
      await first;
      encoder.pending = Completer<Uint8List>();
      final second = encodeImageExport(payload, ImageExportFormat.avif);
      encoder.pending.completeError(StateError('native failure'));
      await expectLater(second, throwsStateError);
      encoder.pending = Completer<Uint8List>();
      final third = encodeImageExport(payload, ImageExportFormat.avif);
      encoder.pending.complete(Uint8List(0));
      await expectLater(third, throwsFormatException);
      expect(encoder.calls, 3);
    },
  );
  testWidgets('timeout retains AVIF gate until native work really completes', (
    tester,
  ) async {
    encoder.pending = Completer<Uint8List>();
    final first = encodeImageExport(payload, ImageExportFormat.avif);
    final timeout = expectLater(first, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 61));
    await timeout;
    await expectLater(
      encodeImageExport(payload, ImageExportFormat.avif),
      throwsStateError,
    );
    encoder.pending.complete(Uint8List.fromList([1]));
    await tester.pump();
    encoder.pending = Completer<Uint8List>();
    final next = encodeImageExport(payload, ImageExportFormat.avif);
    encoder.pending.complete(Uint8List.fromList([1]));
    await next;
  });
}
