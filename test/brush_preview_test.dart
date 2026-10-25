import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/brush_preview.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/document.dart';

void main() {
  for (final tool in ['pencil', 'line', 'rectangle', 'ellipse', 'spray']) {
    for (final filled in [false, true]) {
      for (final mirrored in [false, true]) {
        test(
          '$tool filled=$filled mirrored=$mirrored preview matches committed pixels',
          () {
            final engine = EditorEngine()
              ..document = SpriteDocument.create(16, 16);
            final points = [
              const Offset(2, 3),
              const Offset(7, 5),
              const Offset(11, 12),
            ];
            final args = <String, dynamic>{
              'tool': tool,
              'points': points
                  .map((p) => [p.dx.toInt(), p.dy.toInt()])
                  .toList(),
              'size': 3,
              'color': 0xffabcdef,
              'filled': filled,
              'mirrorX': mirrored,
              'mirrorY': mirrored,
              'seed': 123456,
              'density': 24,
            };
            engine.stroke(args);
            final expected = engine.document
                .composite(0)
                .map((v) => v == 0 ? 0 : 1)
                .toList();
            final actual = previewStrokeMask(
              width: 16,
              height: 16,
              tool: tool,
              points: points,
              size: 3,
              filled: filled,
              mirrorX: mirrored,
              mirrorY: mirrored,
              seed: 123456,
              density: 24,
            );
            expect(actual, expected);
            final runs = previewStrokeRuns(
              width: 16,
              height: 16,
              tool: tool,
              points: points,
              size: 3,
              filled: filled,
              mirrorX: mirrored,
              mirrorY: mirrored,
              seed: 123456,
              density: 24,
            );
            final sparse = List<int>.filled(256, 0);
            for (final run in runs) {
              for (var x = run.left.toInt(); x < run.right.toInt(); x++) {
                sparse[run.top.toInt() * 16 + x] = 1;
              }
            }
            expect(sparse, expected, reason: 'bounded run preview');
          },
        );
      }
    }
  }
}
