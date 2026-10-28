import 'dart:convert';
import 'dart:typed_data';

import '../engine/aseprite.dart';
import '../engine/document.dart';
import 'draft_storage.dart';
import 'draft_worker.dart' if (dart.library.js_interop) 'draft_worker_web.dart';

class DraftInfo {
  const DraftInfo({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.width = 0,
    this.height = 0,
    this.frames = 0,
    this.error,
    this.fallback = false,
  });
  final int id, updatedAt, width, height, frames;
  final String title;
  final String? error;
  final bool fallback;
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt,
    'width': width,
    'height': height,
    'frames': frames,
    'error': error,
    'fallback': fallback,
  };
}

class DraftSnapshot {
  const DraftSnapshot(this.info, this.document, this.source);
  final DraftInfo info;
  final SpriteDocument document;

  /// Provenance only. It never restores a writable path or URI permission.
  final String? source;
}

/// Every draft is self-describing: no shared manifest can orphan other work.
/// There is no age-based eviction. At capacity, writes fail visibly and retain
/// the last good copy; only Save/explicit discard remove drafts.
class DraftRepository {
  DraftRepository(
    this.storage, {
    this.maxBytes = 256 * 1024 * 1024,
    this.maxDrafts = 64,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);
  final DraftStorage storage;
  final int maxBytes, maxDrafts;
  final int Function() _now;
  static const maxRecordBytes = AsepriteCodec.maxFile + 16384;
  static const _magic = [83, 68, 68, 49]; // SDD1

  static int _checksum(Uint8List bytes) {
    var a = 1, b = 0;
    for (var start = 0; start < bytes.length; start += 5552) {
      final end = (start + 5552).clamp(0, bytes.length);
      for (var index = start; index < end; index++) {
        a += bytes[index];
        b += a;
      }
      a %= 65521;
      b %= 65521;
    }
    return b * 65536 + a;
  }

  static DraftSnapshot _decode(int id, Uint8List bytes, bool fallback) {
    if (bytes.length > maxRecordBytes) {
      throw const FormatException('Draft exceeds the safety limit');
    }
    var title = 'Recovered $id';
    String? source;
    var updated = 0;
    var payload = bytes;
    if (bytes.length >= 12 &&
        bytes[0] == _magic[0] &&
        bytes[1] == _magic[1] &&
        bytes[2] == _magic[2] &&
        bytes[3] == _magic[3]) {
      final header = ByteData.sublistView(bytes);
      final length = header.getUint32(4);
      if (_checksum(Uint8List.sublistView(bytes, 12)) != header.getUint32(8)) {
        throw const FormatException('Draft checksum mismatch');
      }
      if (length > 16372 || length + 12 > bytes.length) {
        throw const FormatException('Invalid draft metadata');
      }
      final json = jsonDecode(utf8.decode(bytes.sublist(12, length + 12)));
      if (json is! Map || json['version'] != 1 || json['id'] != id) {
        throw const FormatException('Invalid draft identity');
      }
      title = json['title'] as String;
      source = json['source'] as String?;
      updated = (json['updatedAt'] as num).toInt();
      payload = Uint8List.sublistView(bytes, length + 12);
    }
    final document = AsepriteCodec.decode(payload);
    return DraftSnapshot(
      DraftInfo(
        id: id,
        title: title,
        updatedAt: updated,
        width: document.width,
        height: document.height,
        frames: document.frames.length,
        fallback: fallback,
      ),
      document,
      source,
    );
  }

  Future<DraftSnapshot> load(int id) async {
    final candidates = await storage.read(id);
    for (var index = 0; index < candidates.length; index++) {
      try {
        final bytes = candidates[index];
        if (bytes.length > maxRecordBytes) continue;
        return await draftWork(() => _decode(id, bytes, index > 0));
      } catch (_) {
        // A damaged newest generation must not hide the last good generation.
      }
    }
    throw const FormatException(
      'This draft could not be read. Its stored copies have been kept.',
    );
  }

  Future<List<DraftInfo>> list() async {
    final result = <DraftInfo>[];
    for (final id in await storage.ids()) {
      try {
        result.add((await load(id)).info);
      } catch (_) {
        result.add(
          DraftInfo(
            id: id,
            title: 'Unreadable draft $id',
            updatedAt: 0,
            error:
                'Stored copies could not be read; other drafts are unaffected.',
          ),
        );
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<DraftInfo> save({
    required int id,
    required String title,
    String? source,
    required SpriteDocument document,
  }) async {
    final updated = _now();
    final bytes = await draftWork(() {
      final encoded = AsepriteCodec.encode(document);
      AsepriteCodec.decode(encoded);
      final metadata = utf8.encode(
        jsonEncode({
          'version': 1,
          'id': id,
          'title': title,
          'source': source,
          'updatedAt': updated,
        }),
      );
      if (metadata.length > 16372) {
        throw const FormatException('Draft metadata exceeds the safety limit');
      }
      final body =
          (BytesBuilder(copy: false)
                ..add(metadata)
                ..add(encoded))
              .takeBytes();
      return (BytesBuilder(copy: false)
            ..add(_magic)
            ..add(
              (ByteData(4)..setUint32(0, metadata.length)).buffer.asUint8List(),
            )
            ..add(
              (ByteData(4)..setUint32(0, _checksum(body))).buffer.asUint8List(),
            )
            ..add(body))
          .takeBytes();
    });
    final ids = await storage.ids();
    if (!ids.contains(id) && ids.length >= maxDrafts) {
      throw StateError(
        'Draft storage is full. Save or discard an older draft.',
      );
    }
    Uint8List? previous;
    for (final candidate in await storage.read(id)) {
      try {
        await draftWork(() => _decode(id, candidate, false));
        previous = candidate;
        break;
      } catch (_) {}
    }
    // Budget peak storage, not only the final renamed generations. Count
    // corrupt/oversized files too; they remain user work until explicit discard.
    var occupied = 0;
    if (storage case final SizedDraftStorage sized) {
      occupied = await sized.totalBytes();
    } else {
      for (final other in ids) {
        for (final candidate in await storage.read(other)) {
          occupied += candidate.length;
        }
      }
    }
    final size = occupied + bytes.length + (previous?.length ?? 0);
    if (size > maxBytes) {
      throw StateError(
        'Draft storage is full. Save or discard an older draft.',
      );
    }
    await storage.write(id, bytes, previous: previous);
    return DraftInfo(
      id: id,
      title: title,
      updatedAt: updated,
      width: document.width,
      height: document.height,
      frames: document.frames.length,
    );
  }

  Future<void> delete(int id) => storage.delete(id);
}
