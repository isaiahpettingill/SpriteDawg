import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/canvas_view_mode.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/pixel_canvas.dart';

void main() {
  for (final mode in CanvasViewMode.values) {
    for (final tool in ['pencil', 'fill', 'eyedropper', 'selectRegion']) {
      testWidgets('two fingers pan in $tool / $mode without changing tools', (t) async {
        final e = Editor(transport: (_, _) async => null);
        e.state = {'width': 8, 'height': 8};
        final strokes = <List<Offset>>[];
        Future<void> host(String value, {bool navigationOnly = false}) =>
            t.pumpWidget(MaterialApp(home: Center(child: SizedBox(
              width: 320, height: 320,
              child: PixelCanvas(
                editor: e, tool: value, navigationOnly: navigationOnly,
                color: 0xff123456, brush: 1, grid: false, onion: false,
                fitToken: 0, viewMode: mode, onPick: (_) {},
                onStroke: (_, points) => strokes.add(points),
              ),
            ))));
        await host(tool);
        final center = t.getCenter(find.byKey(const Key('pixel-canvas')));
        final a = await t.startGesture(center - const Offset(20, 0), pointer: 1);
        await a.moveBy(const Offset(5, 0));
        final b = await t.startGesture(center + const Offset(20, 0), pointer: 2);
        final completed = strokes.length;
        expect(completed, tool == 'pencil' || tool == 'fill' ? 1 : 0);
        await a.moveBy(const Offset(24, 12));
        await b.moveBy(const Offset(24, 12));
        await b.up();
        await a.moveBy(const Offset(70, 50));
        await a.up();
        expect(strokes.length, completed);
        expect(t.widget<PixelCanvas>(find.byType(PixelCanvas)).tool, tool);
        await host('pencil');
        await t.tapAt(center + const Offset(24, 12));
        expect(strokes.last.single.dx, closeTo(4, .0001));
        expect(strokes.last.single.dy, closeTo(4, .0001));
        await t.pumpWidget(const SizedBox());
        e.dispose();
      });
    }
  }
  testWidgets('playback stays read-only without selecting a Pan tool', (t) async {
    final e = Editor(transport: (_, _) async => null);
    var strokes = 0;
    await t.pumpWidget(MaterialApp(home: PixelCanvas(
      editor: e, tool: 'pencil', navigationOnly: true,
      color: 0, brush: 1, grid: false, onion: false, fitToken: 0,
      onPick: (_) {}, onStroke: (_, _) => strokes++,
    )));
    await t.drag(find.byKey(const Key('pixel-canvas')), const Offset(30, 20));
    expect(strokes, 0);
    expect(t.widget<PixelCanvas>(find.byType(PixelCanvas)).tool, 'pencil');
    await t.pumpWidget(const SizedBox());
    e.dispose();
  });
}
