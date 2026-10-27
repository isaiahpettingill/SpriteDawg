import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/default_user_data_store.dart';

void main() {
  test(
    'persists raw text over restart, empty clears, save failure retains prior',
    () async {
      var disk = '', fail = false;
      DefaultUserDataStore store() => DefaultUserDataStore(
        read: () async => disk,
        write: (value) async {
          if (fail) throw StateError('full');
          disk = value;
        },
      );
      const raw = ' credits="A"\ntitle=""\nlicense="CC0"\n';
      await store().save(raw);
      expect(await store().load(), raw);
      fail = true;
      await expectLater(store().save('new'), throwsStateError);
      expect(await store().load(), raw);
      fail = false;
      await store().save('');
      expect(await store().load(), '');
    },
  );
  test(
    'missing defaults, invalid storage, size cap and serialized writes',
    () async {
      final memory = DefaultUserDataStore.memory();
      expect(await memory.load(), '');
      await Future.wait([memory.save('first'), memory.save('last')]);
      expect(await memory.load(), 'last');
      await expectLater(memory.save('é' * 32768), throwsFormatException);
      expect(await memory.load(), 'last');
      final bad = DefaultUserDataStore(
        read: () async => 'x' * 65536,
        write: (_) async {},
      );
      await expectLater(bad.load(), throwsFormatException);
      final invalid = DefaultUserDataStore(
        read: () async => throw const FormatException('Invalid UTF8'),
        write: (_) async {},
      );
      await expectLater(invalid.load(), throwsFormatException);
    },
  );
}
