import 'package:spritedawg/engine/palette_presets.dart';
import 'package:spritedawg/user_palette_store.dart';

class MemoryPaletteStore extends UserPaletteStore {
  MemoryPaletteStore() : super(() => throw UnsupportedError('No file access'));
  final List<PalettePreset> entries = [];
  bool failLoad = false;
  bool failSave = false;
  int sequence = 0;
  @override
  Future<List<PalettePreset>> load() async {
    if (failLoad) throw const FormatException('Corrupt library');
    return List.unmodifiable(entries);
  }

  @override
  Future<PalettePreset> save({
    required String name,
    required List<int> colors,
    List<String> colorNames = const [],
    String? replaceId,
  }) async {
    if (failSave) throw StateError('Write failed');
    var unique = name;
    var suffix = 2;
    while (entries.any((p) => p.id != replaceId && p.name == unique)) {
      unique = '$name (${suffix++})';
    }
    final result = PalettePreset.user(
      id: replaceId ?? 'user-${sequence++}',
      name: unique,
      colors: colors,
      colorNames: colorNames,
    );
    final index = entries.indexWhere((p) => p.id == replaceId);
    if (index >= 0) {
      entries[index] = result;
    } else {
      entries.add(result);
    }
    return result;
  }

  @override
  Future<void> delete(String id) async {
    entries.removeWhere((p) => p.id == id);
  }
}
