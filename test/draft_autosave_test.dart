import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/drafts/draft_autosave.dart';

void main() {
  testWidgets(
    'coalesces multiple IDs, bounded continuous edits, forget prevents late resurrection',
    (tester) async {
      final batches = <List<int>>[];
      late DraftAutosave saver;
      saver = DraftAutosave(
        flush: () async {
          batches.add(saver.takePending());
        },
      );
      saver.mark(1);
      saver.mark(2);
      saver.forget(1);
      await tester.pump(const Duration(milliseconds: 499));
      expect(batches, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(batches, [
        [2],
      ]);
      for (var n = 0; n < 6; n++) {
        saver.mark(3);
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(batches.where((b) => b.contains(3)).length, 1);
      saver.forget(3);
      await tester.pump(const Duration(seconds: 1));
      expect(batches.length, 2);
      saver.dispose();
    },
  );
}
