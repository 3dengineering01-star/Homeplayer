import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/services/track_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A music server that serves byte ranges, like Jellyfin and Navidrome, and needs its token.
Future<HttpServer> _musicServer(List<int> song, List<String> asked) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    asked.add('${req.uri.path} ${req.headers.value('range') ?? 'all'}');
    final res = req.response;
    if (req.headers.value('authorization') != 'token') {
      res.statusCode = 401;
      await res.close();
      return;
    }
    final r = parseRange(req.headers.value('range'), song.length)!;
    res.statusCode = req.headers.value('range') == null ? 200 : 206;
    res.headers.set('content-type', 'audio/flac');
    res.headers.set('accept-ranges', 'bytes');
    if (res.statusCode == 206) res.headers.set('content-range', 'bytes ${r.start}-${r.end}/${song.length}');
    res.contentLength = r.end - r.start + 1;
    res.add(song.sublist(r.start, r.end + 1));
    await res.close();
  });
  return server;
}

Future<(int, List<int>)> _get(Uri url, {String? range}) async {
  final client = HttpClient();
  final req = await client.getUrl(url);
  if (range != null) req.headers.set('range', range);
  final res = await req.close();
  final body = [for (final chunk in await res.toList()) ...chunk];
  client.close();
  return (res.statusCode, body);
}

void main() {
  test('the Range header: all, from a byte, a span, the last bytes, past the end', () {
    expect(parseRange(null, 100), (start: 0, end: 99));
    expect(parseRange('bytes=10-', 100), (start: 10, end: 99));
    expect(parseRange('bytes=10-19', 100), (start: 10, end: 19));
    expect(parseRange('bytes=10-500', 100), (start: 10, end: 99));
    expect(parseRange('bytes=-30', 100), (start: 70, end: 99));
    expect(parseRange('bytes=100-', 100), isNull);
    expect(parseRange('lines=1-2', 100), isNull);
    expect(totalFromContentRange('bytes 100-199/5000'), 5000);
    expect(totalFromContentRange('bytes 0-1/*'), isNull);
  });

  test('a song saved at another size is another file; names are safe for the disk', () {
    const ref = TrackRef(TrackSource.jellyfin, 'abc', accountId: 'a/1');
    expect(cacheKey(ref, Uri.parse('http://nas/Audio/abc/stream?static=true')), 'jellyfin-a_1-abc-0');
    expect(cacheKey(ref, Uri.parse('http://nas/Audio/abc/universal?MaxStreamingBitrate=192000')), 'jellyfin-a_1-abc-192');
    expect(cacheKey(const TrackRef(TrackSource.subsonic, 's1'), Uri.parse('http://nas/rest/stream?id=s1&maxBitRate=128')),
        'subsonic--s1-128');
  });

  test('the oldest songs go first, never the ones playing or saved ahead', () {
    final files = [
      (name: 'old', size: 400, used: DateTime(2026, 1, 1)),
      (name: 'playing', size: 400, used: DateTime(2026, 1, 2)),
      (name: 'newer', size: 400, used: DateTime(2026, 1, 3)),
      (name: 'newest', size: 400, used: DateTime(2026, 1, 4)),
    ];
    expect(toEvict(files, 1000, {'playing'}), ['old', 'newer']);
    expect(toEvict(files, 2000, {}), isEmpty);
  });

  test('the next songs are saved and then played from the phone; a song not saved comes through', () async {
    SharedPreferences.setMockInitialValues({});
    final folder = await Directory.systemTemp.createTemp('songs');
    addTearDown(() => folder.delete(recursive: true));
    final song = [for (var i = 0; i < 300000; i++) i % 251];
    final asked = <String>[];
    final server = await _musicServer(song, asked);
    addTearDown(server.close);
    PlayItem item(String id) => PlayItem(
          title: id,
          url: Uri.parse('http://127.0.0.1:${server.port}/Audio/$id/stream?static=true'),
          isVideo: false,
          headers: const {'authorization': 'token'},
          ref: TrackRef(TrackSource.jellyfin, id, accountId: 'a'),
        );
    final cache = TrackCache.inFolder(folder);
    expect(await cache.start(), isTrue);
    final queue = [item('one'), item('two'), item('three')];
    final urls = [for (final i in queue) cache.urlFor(i)!];
    expect(urls.first.host, '127.0.0.1');
    expect(urls.first.toString(), isNot(contains('token')), reason: 'mpv never sees the token');

    // Playing the first: the second and third are saved.
    cache.follow(queue, 0);
    for (var i = 0; i < 100 && !File('${folder.path}/jellyfin-a-three-0').existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(File('${folder.path}/jellyfin-a-two-0').lengthSync(), song.length);
    expect(File('${folder.path}/jellyfin-a-three-0').lengthSync(), song.length);
    expect(asked.where((a) => a.contains('/one/')), isEmpty, reason: 'the playing song is left to mpv');

    // A saved song is served from the phone, also a part of it, without asking the server.
    asked.clear();
    final (status, body) = await _get(urls[1], range: 'bytes=1000-1999');
    expect(status, 206);
    expect(body, song.sublist(1000, 2000));
    expect(asked, isEmpty);

    // The playing song, not saved, comes through from the server with mpv's range.
    final (status2, body2) = await _get(urls[0], range: 'bytes=5-9');
    expect(status2, 206);
    expect(body2, song.sublist(5, 10));
    expect(asked.single, '/Audio/one/stream bytes=5-9');

    // Someone else's guess of the address gets nothing.
    final (status3, _) = await _get(urls[0].replace(path: '/nope/jellyfin-a-one-0'));
    expect(status3, 404);
    cache.follow(const [], 0);
  });

  test('a download cut off goes on from the byte it reached', () async {
    SharedPreferences.setMockInitialValues({});
    final folder = await Directory.systemTemp.createTemp('songs');
    addTearDown(() => folder.delete(recursive: true));
    final song = [for (var i = 0; i < 200000; i++) i % 249];
    final asked = <String>[];
    final server = await _musicServer(song, asked);
    addTearDown(server.close);
    PlayItem item(String id) => PlayItem(
          title: id,
          url: Uri.parse('http://127.0.0.1:${server.port}/Audio/$id/stream'),
          isVideo: false,
          headers: const {'authorization': 'token'},
          ref: TrackRef(TrackSource.jellyfin, id, accountId: 'a'),
        );
    File('${folder.path}/jellyfin-a-next-0.part').writeAsBytesSync(song.sublist(0, 120000));
    final cache = TrackCache.inFolder(folder);
    await cache.start();
    cache.follow([item('now'), item('next')], 0);
    final saved = File('${folder.path}/jellyfin-a-next-0');
    for (var i = 0; i < 100 && !saved.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(saved.readAsBytesSync(), song);
    expect(asked.single, '/Audio/next/stream bytes=120000-');
    cache.follow(const [], 0);
  });
}
