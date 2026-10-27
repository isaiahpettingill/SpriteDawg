import 'package:flutter/foundation.dart';
import 'dart:isolate';

/// Browsers do not expose Dart isolates. Yield once before bounded work so the
/// progress UI can render; native builds retain background isolates.
Future<T> runBackground<T>(T Function() action) async {
  if (!kIsWeb) return Isolate.run(action);
  await Future<void>.delayed(Duration.zero);
  return action();
}
