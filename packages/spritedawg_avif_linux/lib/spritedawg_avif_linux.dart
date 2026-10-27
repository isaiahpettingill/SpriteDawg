import 'dart:ffi';
import 'package:flutter_avif_platform_interface/flutter_avif_platform_interface.dart';

/// Loads the bridge built for the current Linux architecture, never a bundled
/// x86-only upstream prebuilt. Flutter invokes this during plugin registration.
class SpritedawgAvifLinux extends FlutterAvifPlatform {
  static void registerWith() {
    FlutterAvifPlatform.api = FlutterAvifImpl(
      DynamicLibrary.open('libflutter_avif.so'),
    );
  }
}
