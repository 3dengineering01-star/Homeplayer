import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Covers, posters and photos from the server, kept on the phone: lists show what was seen
/// before without a connection or on a slow one, and nothing is fetched twice. Files live in
/// the app's own folder, so they stay from one start to the next (the cache folder, where they
/// were before, Android may empty by itself), and the oldest unused go once they pass [maxBytes].
class ArtworkCache {
  ArtworkCache._();

  static final instance = ArtworkCache._();

  static const maxBytes = 300 * 1024 * 1024;

  /// A picture that does not come in this time shows the fallback icon instead.
  static const timeout = Duration(seconds: 20);

  final _http = http.Client();
  Future<Directory?>? _dir;

  /// Pictures being fetched, by file name: the same one asked twice is fetched once.
  final _pending = <String, Future<Uint8List>>{};

  /// Null when the phone gives no folder: pictures then come from the server each time.
  Future<Directory?> _folder() => _dir ??= () async {
        try {
          final d = Directory('${(await getApplicationSupportDirectory()).path}/artwork');
          await d.create(recursive: true);
          // Once per start, after the first pictures are on screen.
          Timer(const Duration(seconds: 30), () {
            unawaited(_prune(d));
            unawaited(_dropOldFolder());
          });
          return d;
        } catch (e) {
          debugPrint('homeplay artwork cache off: ${e.runtimeType}');
          return null;
        }
      }();

  /// The picture's bytes: from the phone when kept, otherwise from the server, then kept.
  /// Throws [ArtworkUnavailable], whose message has no address (the address may carry a token).
  Future<Uint8List> load(Uri url, Map<String, String> headers) {
    final name = artworkCacheName(url);
    return sharedLoad(_pending, name, () => _load(name, url, headers));
  }

  /// Version 0.3.19 kept pictures in the cache folder; they are fetched again into the new one.
  Future<void> _dropOldFolder() async {
    try {
      final old = Directory('${(await getApplicationCacheDirectory()).path}/artwork');
      if (await old.exists()) await old.delete(recursive: true);
    } catch (e) {
      debugPrint('homeplay artwork old folder: ${e.runtimeType}');
    }
  }

  Future<Uint8List> _load(String name, Uri url, Map<String, String> headers) async {
    final dir = await _folder();
    final file = dir == null ? null : File('${dir.path}/$name');
    if (file != null) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          // Used now: the oldest unused go first when the folder is pruned.
          unawaited(file.setLastModified(DateTime.now()).then((_) {}, onError: (_) {}));
          return bytes;
        }
      } on FileSystemException {
        // Not kept yet.
      }
    }
    final http.Response res;
    try {
      res = await _http.get(url, headers: headers).timeout(timeout);
    } catch (e) {
      throw ArtworkUnavailable(e is TimeoutException ? 'timeout' : e.runtimeType.toString());
    }
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) throw ArtworkUnavailable('status ${res.statusCode}');
    if (file != null) {
      // Written aside and renamed, so a half-written file is never read as a picture.
      try {
        final part = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.part');
        await part.writeAsBytes(res.bodyBytes, flush: true);
        await part.rename(file.path);
      } catch (e) {
        debugPrint('homeplay artwork not kept: ${e.runtimeType}');
      }
    }
    return res.bodyBytes;
  }

  /// Drops the kept copy of [url], when it turned out not to be a picture.
  Future<void> forget(Uri url) async {
    final dir = await _folder();
    if (dir == null) return;
    await File('${dir.path}/${artworkCacheName(url)}').delete().then((_) {}, onError: (_) {});
  }

  Future<void> _prune(Directory dir) async {
    try {
      final files = <CachedFile>[];
      await for (final f in dir.list()) {
        if (f is! File) continue;
        final s = await f.stat();
        files.add((path: f.path, size: s.size, used: s.modified));
      }
      for (final path in artworkToPrune(files, maxBytes)) {
        await File(path).delete().then((_) {}, onError: (_) {});
      }
    } catch (e) {
      debugPrint('homeplay artwork prune: ${e.runtimeType}');
    }
  }
}

/// [start]'s future for [key], shared by everyone who asks while it runs, and forgotten from
/// [pending] once it is done, with a picture or an error. Pure.
///
/// The forgetting must not hand back a future: a whenComplete callback returning the removed
/// entry (which is this very future) made it wait for itself, and no picture ever showed.
Future<T> sharedLoad<T>(Map<String, Future<T>> pending, String key, Future<T> Function() start) {
  final running = pending[key];
  if (running != null) return running;
  final future = start();
  pending[key] = future;
  future.then<void>((_) {
    pending.remove(key);
  }, onError: (Object _) {
    pending.remove(key);
  });
  return future;
}

/// A picture that could not be had. The message never has the address.
class ArtworkUnavailable implements Exception {
  ArtworkUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'Artwork unavailable: $reason';
}

/// Query parameters that carry the sign-in (Jellyfin's api_key, Subsonic's u, t, s, p): left
/// out of the file name so a new sign-in still finds the pictures kept.
const _signInParams = {'api_key', 'apikey', 'token', 'u', 't', 's', 'p', 'c', 'v'};

/// The file name for a picture's address: a hash of the address without its sign-in, its
/// other parameters in a fixed order. Pure; the name never shows the address.
String artworkCacheName(Uri url) {
  final kept = url.queryParametersAll.entries.where((e) => !_signInParams.contains(e.key.toLowerCase())).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final query = [
    for (final e in kept)
      for (final v in e.value) '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(v)}',
  ].join('&');
  final stable = '${url.scheme}://${url.host.toLowerCase()}:${url.port}${url.path}?$query';
  return sha1.convert(utf8.encode(stable)).toString();
}

typedef CachedFile = ({String path, int size, DateTime used});

/// The files to delete so the rest fit in [maxBytes]: the longest unused go first. Pure.
List<String> artworkToPrune(List<CachedFile> files, int maxBytes) {
  final newest = [...files]..sort((a, b) => b.used.compareTo(a.used));
  var total = 0;
  final drop = <String>[];
  for (final f in newest) {
    total += f.size;
    if (total > maxBytes) drop.add(f.path);
  }
  return drop;
}

/// An [ImageProvider] over [ArtworkCache]. Two providers for the same address are the same
/// picture in Flutter's memory cache; [toString] never shows the address.
class CachedArtwork extends ImageProvider<CachedArtwork> {
  const CachedArtwork(this.url, {this.headers = const {}});

  final Uri url;

  /// Sent with the request (Jellyfin's sign-in); not part of what makes two pictures the same.
  final Map<String, String> headers;

  @override
  Future<CachedArtwork> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedArtwork key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1);

  Future<ui.Codec> _load(CachedArtwork key, ImageDecoderCallback decode) async {
    final bytes = await ArtworkCache.instance.load(key.url, key.headers);
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // An error page or a damaged file: fetched again next time.
      await ArtworkCache.instance.forget(key.url);
      throw ArtworkUnavailable('not a picture');
    }
  }

  @override
  bool operator ==(Object other) => other is CachedArtwork && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'CachedArtwork(${artworkCacheName(url).substring(0, 8)})';
}
