import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/brush_preview.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/document.dart';

void main() {
  for (final dimensions in [(1, 1), (8, 8), (9, 6), (5, 11)]) {
    for (final tool in [
      'pencil',
      'eraser',
      'line',
      'rectangle',
      'ellipse',
      'spray',
    ]) {
      for (final filled in [false, true]) {
        test(
          '$dimensions $tool filled=$filled wrapped preview matches commit',
          () {
            final (w, h) = dimensions;
            final points = [
              Offset(-2, -1),
              Offset(1, 1),
              Offset(w + 1.0, h - 1.0),
            ];
            final engine = EditorEngine()
              ..document = SpriteDocument.create(w, h);
            if (tool == 'eraser') {
              engine.stroke({
                'tool': 'rectangle',
                'filled': true,
                'color': 0xffabcdef,
                'points': [
                  [0, 0],
                  [w - 1, h - 1],
                ],
              });
            }
            engine.stroke({
              'tool': tool,
              'size': 3,
              'filled': filled,
              'wrap': true,
              'points': points
                  .map((p) => [p.dx.floor(), p.dy.floor()])
                  .toList(),
              'color': 0x80ff0000,
              'mirrorDiagonal': true,
              'mirrorAntiDiagonal': true,
              'seed': 19,
            });
            final expected = engine.document
                .composite(0)
                .map(
                  (p) => tool == 'eraser' ? (p == 0 ? 1 : 0) : (p == 0 ? 0 : 1),
                )
                .toList();
            final mask = previewStrokeMask(
              width: w,
              height: h,
              tool: tool,
              points: points,
              size: 3,
              filled: filled,
              wrap: true,
              mirrorDiagonal: true,
              mirrorAntiDiagonal: true,
              seed: 19,
            );
            expect(mask, expected);
            final actual = List<int>.filled(w * h, 0);
            for (final run in previewStrokeRuns(
              width: w,
              height: h,
              tool: tool,
              points: points,
              size: 3,
              filled: filled,
              wrap: true,
              mirrorDiagonal: true,
              mirrorAntiDiagonal: true,
              seed: 19,
            )) {
              for (var x = run.left.toInt(); x < run.right.toInt(); x++) {
                actual[run.top.toInt() * w + x]++;
              }
            }
            expect(
              actual,
              expected,
              reason: 'Wrapped overlaps must emit one run per pixel',
            );
          },
        );
      }
    }
  }
  test(
    'very large wrapped filled preview stays bounded to original canvas',
    () {
      final runs = previewStrokeRuns(
        width: 32,
        height: 17,
        tool: 'ellipse',
        points: const [Offset(-8192, -8192), Offset(8192, 8192)],
        size: 1,
        filled: true,
        wrap: true,
        mirrorDiagonal: true,
      );
      expect(runs.length, 17);
      expect(
        runs.every((r) => r.left == 0 && r.width == 32 && r.height == 1),
        isTrue,
      );
    },
  );

  for (final tool in ['rectangle', 'ellipse']) {
    for (final filled in [false, true]) {
      test(
        '$tool off-canvas filled=$filled source matches clipped diagonal commit',
        () {
          final engine = EditorEngine()
            ..document = SpriteDocument.create(5, 11);
          const points = [Offset(-3, 2), Offset(3, 8)];
          engine.stroke({
            'tool': tool,
            'points': [
              [-3, 2],
              [3, 8],
            ],
            'size': 1,
            'color': 0x80ff0000,
            'filled': filled,
            'mirrorDiagonal': true,
            'mirrorAntiDiagonal': true,
          });
          final expected = engine.document
              .composite(0)
              .map((p) => p == 0 ? 0 : 1)
              .toList();
          expect(
            previewStrokeMask(
              width: 5,
              height: 11,
              tool: tool,
              points: points,
              size: 1,
              filled: filled,
              mirrorDiagonal: true,
              mirrorAntiDiagonal: true,
            ),
            expected,
          );
          final actual = List<int>.filled(55, 0);
          for (final run in previewStrokeRuns(
            width: 5,
            height: 11,
            tool: tool,
            points: points,
            size: 1,
            filled: filled,
            mirrorDiagonal: true,
            mirrorAntiDiagonal: true,
          )) {
            for (var x = run.left.toInt(); x < run.right.toInt(); x++) {
              actual[run.top.toInt() * 5 + x]++;
            }
          }
          expect(actual, expected);
        },
      );
    }
  }
  test(
    'extreme filled preview bounds allocation and emits one run per row',
    () {
      final runs = previewStrokeRuns(
        width: 32,
        height: 17,
        tool: 'rectangle',
        points: const [Offset(-8192, -8192), Offset(8192, 8192)],
        size: 1,
        filled: true,
        mirrorDiagonal: true,
        mirrorAntiDiagonal: true,
      );
      expect(runs.length, 17);
      expect(
        runs.every((r) => r.left == 0 && r.width == 32 && r.height == 1),
        isTrue,
      );
    },
  );
  for (final dimensions in [(8, 8), (9, 9), (12, 8), (9, 6), (6, 9)]) {
    for (final flags in [
      (false, false, true, false),
      (false, false, false, true),
      (false, false, true, true),
      (true, false, true, false),
      (true, true, true, true),
    ]) {
      for (final tool in ['pencil', 'line', 'rectangle', 'ellipse', 'spray']) {
        test('$dimensions $flags $tool diagonal preview matches commit', () {
          final (width, height) = dimensions;
          final points = [
            Offset.zero,
            const Offset(3, 2),
            Offset(4, (height - 1).toDouble()),
          ];
          final engine = EditorEngine()
            ..document = SpriteDocument.create(width, height);
          engine.stroke({
            'tool': tool,
            'points': points.map((p) => [p.dx.toInt(), p.dy.toInt()]).toList(),
            'size': 4,
            'color': 0xffabcdef,
            'mirrorX': flags.$1,
            'mirrorY': flags.$2,
            'mirrorDiagonal': flags.$3,
            'mirrorAntiDiagonal': flags.$4,
            'seed': 123,
          });
          final expected = engine.document
              .composite(0)
              .map((v) => v == 0 ? 0 : 1)
              .toList();
          final mask = previewStrokeMask(
            width: width,
            height: height,
            tool: tool,
            points: points,
            size: 4,
            mirrorX: flags.$1,
            mirrorY: flags.$2,
            mirrorDiagonal: flags.$3,
            mirrorAntiDiagonal: flags.$4,
            seed: 123,
          );
          expect(mask, expected);
          final runs = previewStrokeRuns(
            width: width,
            height: height,
            tool: tool,
            points: points,
            size: 4,
            mirrorX: flags.$1,
            mirrorY: flags.$2,
            mirrorDiagonal: flags.$3,
            mirrorAntiDiagonal: flags.$4,
            seed: 123,
          );
          final sparse = List<int>.filled(width * height, 0);
          for (final run in runs) {
            expect(run.left, greaterThanOrEqualTo(0));
            expect(run.right, lessThanOrEqualTo(width));
            expect(run.top, greaterThanOrEqualTo(0));
            expect(run.bottom, lessThanOrEqualTo(height));
            for (var x = run.left.toInt(); x < run.right.toInt(); x++) {
              final i = run.top.toInt() * width + x;
              expect(sparse[i], 0, reason: 'no duplicate alpha overlay');
              sparse[i] = 1;
            }
          }
          expect(sparse, expected);
        });
      }
    }
  }
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
