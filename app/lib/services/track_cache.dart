import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/common.dart';

/// The next songs of the queue, saved on the phone ahead of time, so the music goes on through
/// a tunnel or a dead zone.
///
/// mpv asks for every song through a small server inside the app (on 127.0.0.1, behind a
/// random path). A song already saved is played from the phone; one not saved yet is passed
/// through from the music server as it comes. Meanwhile the next songs of the queue are
/// downloaded one at a time; a song mpv asks for while it is being downloaded is played from the
/// growing file. Old songs are deleted once the folder grows past [limitBytes].
class TrackCache {
  TrackCache._([this._folder]);

  static final instance = TrackCache._();

  /// A cache of its own in [folder], for tests.
  @visibleForTesting
  factory TrackCache.inFolder(Directory folder) => TrackCache._(folder);

  final Directory? _folder;

  /// How many songs after the playing one are saved ahead; 0 turns it off.
  static const choices = [0, 3, 5, 10];
  static const _aheadKey = 'cache_ahead';
  static const defaultAhead = 5;

  /// Space the saved songs may take.
  static const limitBytes = 1024 * 1024 * 1024;

  int _ahead = defaultAhead;
  int get ahead => _ahead;

  Directory? _dir;
  HttpServer? _server;
  Future<bool>? _starting;
  final String _secret = _randomHex(16);
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  /// Where each song comes from, by its key.
  final Map<String, ({Uri url, Map<String, String> headers})> _sources = {};

  /// Songs to have saved, the next one first; songs kept from deletion.
  List<String> _wanted = const [];
  Set<String> _keep = const {};
  Completer<void> _wake = Completer();
  bool _working = false;
  _Download? _active;
  final Map<String, int> _failures = {};

  /// Starts the small server, once. False when it could not start: songs then come straight
  /// from the server, as before.
  Future<bool> start() => _starting ??= _start();

  Future<bool> _start() async {
    try {
      _ahead = (await SharedPreferences.getInstance()).getInt(_aheadKey) ?? defaultAhead;
      final dir = _dir = _folder ?? Directory('${(await getApplicationCacheDirectory()).path}/tracks');
      await dir.create(recursive: true);
      final server = _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) => _serve(r).catchError((Object e) => debugPrint('homeplay song cache: serving failed: $e')));
      return true;
    } catch (e) {
      debugPrint('homeplay song cache not started: $e');
      return false;
    }
  }

  Future<void> setAhead(int songs) async {
    _ahead = songs;
    await (await SharedPreferences.getInstance()).setInt(_aheadKey, songs);
  }

  /// The address mpv opens for [item], once [start] is done; null for what is not saved this
  /// way (video, a downloaded file, a song with no server identity).
  Uri? urlFor(PlayItem item) {
    final server = _server;
    final ref = item.ref;
    if (server == null || ref == null || item.isVideo || item.url.scheme == 'file') return null;
    final key = cacheKey(ref, item.url);
    _sources[key] = (url: item.url, headers: item.headers);
    return Uri.parse('http://127.0.0.1:${server.port}/$_secret/$key');
  }

  /// The queue changed or moved on: save the songs after [current]. An empty list stops.
  void follow(List<PlayItem> items, int current) {
    final keys = <String>[];
    final keep = <String>{};
    for (var i = max(current, 0); i < items.length && i <= current + _ahead; i++) {
      final item = items[i];
      final ref = item.ref;
      if (ref == null || item.isVideo || item.url.scheme == 'file') continue;
      final key = cacheKey(ref, item.url);
      _sources[key] = (url: item.url, headers: item.headers);
      keep.add(key);
      // The playing song is mpv's own business; only the ones after it are fetched.
      if (i > current && _ahead > 0) keys.add(key);
    }
    _keep = keep;
    if (!listEquals(keys, _wanted)) {
      _wanted = keys;
      _failures.clear();
      if (!_wake.isCompleted) _wake.complete();
    }
    if (!_working && _wanted.isNotEmpty && _dir != null) unawaited(_work());
  }

  /// Deletes every saved song.
  Future<void> clear() async {
    final dir = _dir;
    if (dir == null) return;
    for (final f in dir.listSync().whereType<File>()) {
      if (_active?.key != null && f.path.contains(_active!.key)) continue;
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// Bytes the saved songs take now.
  int get usedBytes {
    final dir = _dir;
    if (dir == null || !dir.existsSync()) return 0;
    return dir.listSync().whereType<File>().fold(0, (n, f) => n + f.lengthSync());
  }

  // --- Saving ahead ---

  File _file(String key) => File('${_dir!.path}/$key');
  File _part(String key) => File('${_dir!.path}/$key.part');
  File _type(String key) => File('${_dir!.path}/$key.type');

  bool _saved(String key) => _file(key).existsSync();

  Future<void> _work() async {
    _working = true;
    try {
      while (true) {
        final key = _wanted.where((k) => !_saved(k)).firstOrNull;
        if (key == null) {
          _wake = Completer();
          await _wake.future;
          if (_wanted.isEmpty) return;
          continue;
        }
        if (await _download(key)) {
          _failures.remove(key);
          _evict();
          continue;
        }
        // Taken out of the queue while it downloaded: on to the next one at once.
        if (!_wanted.contains(key)) continue;
        // No network, or the server is not answering: wait longer each time, or for the queue
        // to change.
        final n = _failures[key] = (_failures[key] ?? 0) + 1;
        _wake = Completer();
        await Future.any([_wake.future, Future<void>.delayed(Duration(seconds: min(2 << min(n, 4), 30)))]);
      }
    } finally {
      _working = false;
    }
  }

  /// Downloads one song to its .part file, going on from where an earlier try stopped. True
  /// once it is all saved.
  Future<bool> _download(String key) async {
    final src = _sources[key];
    if (src == null) return false;
    final part = _part(key);
    final have = part.existsSync() ? part.lengthSync() : 0;
    final download = _active = _Download(key, part);
    IOSink? sink;
    try {
      final req = await _http.getUrl(src.url);
      src.headers.forEach(req.headers.set);
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close().timeout(const Duration(seconds: 30));
      final resumed = res.statusCode == HttpStatus.partialContent && have > 0;
      if (res.statusCode != HttpStatus.ok && !resumed) {
        await res.drain<void>().catchError((_) {});
        // Already all there: the server says the range starts past the end.
        if (res.statusCode == HttpStatus.requestedRangeNotSatisfiable && have > 0) return _finish(key, null);
        debugPrint('homeplay song cache: server answered ${res.statusCode}');
        return false;
      }
      download.total = resumed
          ? totalFromContentRange(res.headers.value(HttpHeaders.contentRangeHeader))
          : (res.contentLength >= 0 ? res.contentLength : null);
      sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        download.grown();
        // Taken out of the queue meanwhile: what is saved stays for a later try.
        if (!_wanted.contains(key)) return false;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      final total = download.total;
      if (total != null && part.lengthSync() < total) return false;
      return _finish(key, res.headers.contentType?.mimeType);
    } catch (e) {
      // The address carries the token: only the kind of failure goes to the log.
      debugPrint('homeplay song cache: download stopped (${e.runtimeType})');
      return false;
    } finally {
      await sink?.close().catchError((_) {});
      download.end();
      if (identical(_active, download)) _active = null;
    }
  }

  bool _finish(String key, String? type) {
    _part(key).renameSync(_file(key).path);
    if (type != null) _type(key).writeAsStringSync(type);
    return true;
  }

  void _evict() {
    final dir = _dir;
    if (dir == null) return;
    final files = [
      for (final f in dir.listSync().whereType<File>())
        if (!f.path.endsWith('.type'))
          (name: f.uri.pathSegments.last, size: f.lengthSync(), used: f.lastModifiedSync()),
    ];
    final keep = {..._keep, for (final k in _keep) '$k.part', if (_active != null) '${_active!.key}.part'};
    for (final name in toEvict(files, limitBytes, keep)) {
      try {
        File('${dir.path}/$name').deleteSync();
        final type = File('${dir.path}/${name.replaceAll('.part', '')}.type');
        if (type.existsSync()) type.deleteSync();
      } catch (_) {}
    }
  }

  // --- Serving mpv ---

  Future<void> _serve(HttpRequest req) async {
    final segments = req.uri.pathSegments;
    if (segments.length != 2 || segments[0] != _secret || !_sources.containsKey(segments[1])) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final key = segments[1];
    final file = _file(key);
    if (file.existsSync()) {
      // Played again: it stays longer before the folder is trimmed.
      try {
        file.setLastModifiedSync(DateTime.now());
      } catch (_) {}
      final type = _type(key);
      return _serveFile(req, file, type.existsSync() ? type.readAsStringSync() : null);
    }
    final active = _active;
    if (active != null && active.key == key && active.total != null) return _serveGrowing(req, active);
    return _passThrough(req, _sources[key]!);
  }

  Future<void> _serveFile(HttpRequest req, File file, String? type) async {
    final length = file.lengthSync();
    final res = req.response;
    final range = parseRange(req.headers.value(HttpHeaders.rangeHeader), length);
    if (range == null) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      await res.close();
      return;
    }
    _head(req, range, length, type);
    if (req.method == 'HEAD') return res.close();
    await res.addStream(file.openRead(range.start, range.end + 1));
    await res.close();
  }

  /// The song being saved right now: bytes go out as they arrive.
  Future<void> _serveGrowing(HttpRequest req, _Download d) async {
    final length = d.total!;
    final res = req.response;
    final range = parseRange(req.headers.value(HttpHeaders.rangeHeader), length);
    if (range == null) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await res.close();
      return;
    }
    _head(req, range, length, null);
    if (req.method == 'HEAD') return res.close();
    final raf = await d.part.open();
    try {
      var at = range.start;
      while (at <= range.end) {
        final have = await raf.length();
        if (have > at) {
          await raf.setPosition(at);
          // A piece at a time, each sent before the next is read: mpv takes it at its own pace.
          final chunk = await raf.read(min(min(have, range.end + 1) - at, 256 * 1024));
          res.add(chunk);
          await res.flush();
          at += chunk.length;
          continue;
        }
        // The download stopped short: mpv reconnects from where it got to.
        if (d.ended) break;
        await d.waitForMore();
      }
    } finally {
      await raf.close();
    }
    await res.close();
  }

  void _head(HttpRequest req, ({int start, int end}) range, int length, String? type) {
    final res = req.response;
    final partial = req.headers.value(HttpHeaders.rangeHeader) != null;
    res.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (type != null) res.headers.set(HttpHeaders.contentTypeHeader, type);
    res.contentLength = range.end - range.start + 1;
    if (partial) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes ${range.start}-${range.end}/$length');
  }

  /// A song not saved yet: straight from the music server, with mpv's own range.
  Future<void> _passThrough(HttpRequest req, ({Uri url, Map<String, String> headers}) src) async {
    final res = req.response;
    HttpClientResponse up;
    try {
      final out = await _http.openUrl(req.method == 'HEAD' ? 'HEAD' : 'GET', src.url);
      src.headers.forEach(out.headers.set);
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) out.headers.set(HttpHeaders.rangeHeader, range);
      up = await out.close().timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('homeplay song cache: server not reached (${e.runtimeType})');
      res.statusCode = HttpStatus.badGateway;
      await res.close();
      return;
    }
    res.statusCode = up.statusCode;
    for (final h in [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
    ]) {
      final v = up.headers.value(h);
      if (v != null) res.headers.set(h, v);
    }
    if (up.contentLength >= 0) res.contentLength = up.contentLength;
    try {
      await res.addStream(up.timeout(const Duration(seconds: 30)));
      await res.close();
    } catch (e) {
      // Cut off mid-song: dropping the connection makes mpv reconnect from where it got to.
      try {
        (await res.detachSocket(writeHeaders: false)).destroy();
      } catch (_) {}
    }
  }

  static String _randomHex(int bytes) {
    final r = Random.secure();
    return [for (var i = 0; i < bytes; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }
}

class _Download {
  _Download(this.key, this.part);

  final String key;
  final File part;
  int? total;
  bool ended = false;
  Completer<void> _more = Completer();

  void grown() {
    if (!_more.isCompleted) _more.complete();
  }

  void end() {
    ended = true;
    grown();
  }

  Future<void> waitForMore() async {
    if (_more.isCompleted) _more = Completer();
    await _more.future.timeout(const Duration(seconds: 1), onTimeout: () {});
  }
}

/// The file name a song is saved under: its server, account and id, and the size the server
/// converts it to, if any (the same song at 128 kbps is another file).
String cacheKey(TrackRef ref, Uri url) {
  final q = url.queryParameters;
  final kbps = q['MaxStreamingBitrate'] != null
      ? (int.tryParse(q['MaxStreamingBitrate']!) ?? 0) ~/ 1000
      : int.tryParse(q['maxBitRate'] ?? '') ?? 0;
  final raw = '${ref.source.name}-${ref.accountId ?? ''}-${ref.id}-$kbps';
  return raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}

/// The bytes asked for by an HTTP Range header of a file of [length] bytes: all of it without
/// one; null when the range cannot be served. Only the single ranges players send.
({int start, int end})? parseRange(String? header, int length) {
  if (header == null || header.trim().isEmpty) return length == 0 ? null : (start: 0, end: length - 1);
  final m = RegExp(r'^\s*bytes=(\d*)-(\d*)\s*$').firstMatch(header);
  if (m == null || length == 0) return null;
  final a = m.group(1)!, b = m.group(2)!;
  if (a.isEmpty) {
    // The last N bytes.
    final n = int.tryParse(b);
    if (n == null || n == 0) return null;
    return (start: max(length - n, 0), end: length - 1);
  }
  final start = int.parse(a);
  final end = b.isEmpty ? length - 1 : min(int.parse(b), length - 1);
  if (start >= length || end < start) return null;
  return (start: start, end: end);
}

/// The size in "bytes 100-199/5000"; null when the server does not say.
int? totalFromContentRange(String? header) {
  final m = RegExp(r'/(\d+)\s*$').firstMatch(header ?? '');
  return m == null ? null : int.parse(m.group(1)!);
}

/// Files to delete so that [files] fit in [limit] bytes: the ones played longest ago first,
/// never those in [keep] (the playing song and the ones saved ahead).
List<String> toEvict(List<({String name, int size, DateTime used})> files, int limit, Set<String> keep) {
  var total = files.fold(0, (n, f) => n + f.size);
  final out = <String>[];
  for (final f in [...files]..sort((a, b) => a.used.compareTo(b.used))) {
    if (total <= limit) break;
    if (keep.contains(f.name)) continue;
    out.add(f.name);
    total -= f.size;
  }
  return out;
}

/// "1.2 GB", "340 MB".
String sizeLabel(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
    : '${(bytes / (1024 * 1024)).round()} MB';
