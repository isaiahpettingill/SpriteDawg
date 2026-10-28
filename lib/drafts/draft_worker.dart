import 'dart:isolate';

Future<T> draftWork<T>(T Function() work) => Isolate.run(work);
