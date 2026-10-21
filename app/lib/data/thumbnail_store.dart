import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps one small picture per saved link on the device, the way WhatsApp keeps a link's
/// preview: downloaded once, shrunk to a ~30 KB JPEG, stored for as long as the link exists.
/// It is a store, not a cache: nothing here expires, and cards never touch the network.
class ThumbnailStore {
  ThumbnailStore._(this._dir);

  final Directory _dir;

  /// Widest side kept. 480px is sharp on a grid card yet only a few dozen KB.
  static const maxSide = 480;
  static const _quality = 72;
  static const _maxDownload = 6 * 1024 * 1024;

  /// The store the UI reads from. Set once at start-up by [open].
  static ThumbnailStore? instance;

  static Future<ThumbnailStore> open({Directory? at}) async {
    final base = at ?? Directory(p.join((await getApplicationDocumentsDirectory()).path, 'thumbs'));
    await base.create(recursive: true);
    return instance = ThumbnailStore._(base);
  }

  /// Items store only the file name, because the app folder's full path can change between
  /// app updates.
  File? fileFor(String? name) {
    if (name == null || name.isEmpty) return null;
    final f = File(p.join(_dir.path, name));
    return f.existsSync() ? f : null;
  }

  /// Downloads [imageUrl], shrinks it and keeps it as [itemId]'s thumbnail, replacing any
  /// earlier one. Returns the stored file name, or null when it could not be fetched or read.
  Future<String?> save(String itemId, String imageUrl, {Duration timeout = const Duration(seconds: 10)}) async {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || !uri.hasScheme) return null;
    try {
      final res = await http.get(uri, headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) Shareby'}).timeout(timeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty || res.bodyBytes.length > _maxDownload) return null;
      final jpg = await compute(shrinkToJpeg, res.bodyBytes);
      if (jpg == null) return null;
      return await _write(itemId, jpg);
    } catch (_) {
      return null;
    }
  }

  /// Keeps already-shrunk [jpeg] bytes as [itemId]'s thumbnail.
  Future<String> _write(String itemId, Uint8List jpeg) async {
    // A new name each time: Flutter caches decoded images by file path, so reusing one name
    // would keep showing the old picture after a refresh.
    final name = '${itemId}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final target = File(p.join(_dir.path, name));
    // Write beside it, then swap in, so a crash never leaves half a picture.
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(jpeg, flush: true);
    await temp.rename(target.path);
    await _deleteOthers(itemId, keep: name);
    return name;
  }

  /// Removes this link's earlier pictures.
  Future<void> _deleteOthers(String itemId, {String? keep}) async {
    try {
      await for (final e in _dir.list()) {
        final name = p.basename(e.path);
        if (e is File && name != keep && name.startsWith('${itemId}_')) await e.delete();
      }
    } on FileSystemException {
      // Best effort; [sweep] catches leftovers.
    }
  }

  Future<void> delete(String? name) async {
    final f = fileFor(name);
    if (f != null) {
      try {
        await f.delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  /// Removes pictures no saved link points to any more (links deleted on another device).
  Future<void> sweep(Set<String> keep) async {
    try {
      await for (final e in _dir.list()) {
        if (e is File && !keep.contains(p.basename(e.path))) await e.delete();
      }
    } on FileSystemException {
      // Best effort.
    }
  }
}

/// Decodes any picture format, scales it so its longer side is at most
/// [ThumbnailStore.maxSide] (never enlarging) and re-encodes it as JPEG. Runs on a worker
/// isolate. Returns null for bytes that are not a readable image.
Uint8List? shrinkToJpeg(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    final scaled = longest <= ThumbnailStore.maxSide
        ? decoded
        : (decoded.width >= decoded.height
            ? img.copyResize(decoded, width: ThumbnailStore.maxSide, interpolation: img.Interpolation.average)
            : img.copyResize(decoded, height: ThumbnailStore.maxSide, interpolation: img.Interpolation.average));
    return Uint8List.fromList(img.encodeJpg(scaled, quality: ThumbnailStore._quality));
  } catch (_) {
    return null;
  }
}
