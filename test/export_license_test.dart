import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export codec notices are bundled for offline viewing', () async {
    final notice = await rootBundle.loadString(
      'packages/spritedawg_avif_linux/THIRD_PARTY_NOTICES.txt',
    );
    expect(notice, contains('libavif'));
    expect(notice, contains('imcodec'));
    expect(notice, contains('Hugo Delaunay'));
    expect(notice, contains('Permission is hereby granted'));
  });
}
