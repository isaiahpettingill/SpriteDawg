import 'aseprite.dart';
import 'document.dart';

/// Self-contained snapshot of exactly one named, contiguous Aseprite tag.
SpriteDocument copyTagSection(SpriteDocument source, int index) {
  require(index >= 0 && index < source.tags.length, 'Choose a tag to copy');
  // Codec cloning owns all typed-property and unknown-safe metadata byte arrays.
  final copy = AsepriteCodec.decode(AsepriteCodec.encode(source));
  final tag = copy.tags[index].copy();
  var decodedPixels = 0;
  for (var f = tag.from; f <= tag.to; f++) {
    for (var l = 0; l < copy.layers.length; l++) {
      decodedPixels += copy.resolved(f, l)?.pixels.length ?? 0;
      require(
        decodedPixels <= 16 * 1024 * 1024,
        'Copied tag exceeds the 16 Mi decoded-pixel budget once links are made independent.',
      );
    }
  }
  for (var f = tag.from; f <= tag.to; f++) {
    for (var l = 0; l < copy.layers.length; l++) {
      copy.frames[f].cels[l] = copy.resolved(f, l)?.copy();
    }
  }
  final profiles = copy.frames
      .expand((f) => f.metadata)
      .where((m) => m.type == 0x2007)
      .toList();
  copy.frames = copy.frames.sublist(tag.from, tag.to + 1);
  for (final frame in copy.frames) {
    frame.metadata.removeWhere((m) => m.type == 0x2007);
  }
  copy.frames.first.metadata.insertAll(0, profiles);
  tag.to -= tag.from;
  tag.from = 0;
  copy.tags = [tag];
  return copy;
}

bool _bytes(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == null && b == null;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _data(UserData? a, UserData? b) =>
    a?.text == b?.text &&
    a?.color == b?.color &&
    _bytes(a?.properties, b?.properties);

/// Conservative paste: never silently flatten, quantize or rename layer/tag data.
/// Called on an engine transaction candidate, so any failure leaves it untouched.
void pasteTagSection(SpriteDocument target, int after, SpriteDocument section) {
  require(
    after >= -1 && after < target.frames.length,
    'Invalid paste position',
  );
  require(
    target.width == section.width && target.height == section.height,
    'Tag paste needs matching canvas dimensions. Resize explicitly first.',
  );
  require(
    target.depth == section.depth,
    'Tag paste needs matching color modes. Convert explicitly first.',
  );
  require(
    target.depth != 8 || target.transparentIndex == section.transparentIndex,
    'Tag paste needs matching transparent palette indices. No indices were changed.',
  );
  require(
    target.layers.length == section.layers.length,
    'Tag paste needs matching layers (same names and order). No layers were discarded.',
  );
  for (var i = 0; i < target.layers.length; i++) {
    final a = target.layers[i], b = section.layers[i];
    require(
      a.name == b.name &&
          a.flags == b.flags &&
          a.visible == b.visible &&
          a.opacity == b.opacity &&
          _bytes(a.uuid, b.uuid) &&
          _data(a.data, b.data),
      'Layer ${i + 1} differs in name, order, properties or metadata. Align layers explicitly before pasting.',
    );
  }
  final a = target.frames
      .expand((f) => f.metadata)
      .where((m) => m.type == 0x2007)
      .map((m) => m.bytes)
      .toList();
  final b = section.frames
      .expand((f) => f.metadata)
      .where((m) => m.type == 0x2007)
      .map((m) => m.bytes)
      .toList();
  require(
    a.length == b.length &&
        List.generate(a.length, (i) => _bytes(a[i], b[i])).every((v) => v),
    'Color profile metadata differs; tag paste refused.',
  );
  require(target.tags.length + section.tags.length <= 65535, 'Too many tags');
  final count = section.frames.length;
  require(
    target.frames.length + count <= 4096,
    'Tag paste exceeds 4096 frames',
  );
  final clone = AsepriteCodec.decode(AsepriteCodec.encode(section));
  clone.detachLinks();
  for (final frame in target.frames) {
    for (final cel in frame.cels) {
      if (cel?.link != null && cel!.link! > after) cel.link = cel.link! + count;
    }
  }
  for (final f in clone.frames) {
    f.metadata.removeWhere((m) => m.type == 0x2007);
  }
  for (final tag in target.tags) {
    if (tag.from > after) tag.from += count;
    if (tag.to > after) tag.to += count;
  }
  target.frames.insertAll(after + 1, clone.frames);
  for (final tag in clone.tags) {
    tag.from += after + 1;
    tag.to += after + 1;
    target.tags.add(tag);
  }
  // Includes aggregate decoded-pixel/file limits and validates indexed palettes.
  AsepriteCodec.decode(AsepriteCodec.encode(target));
}
