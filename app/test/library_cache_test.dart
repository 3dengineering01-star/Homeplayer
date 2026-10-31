import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/services/library_cache.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _account = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'me');

/// A library of [count] tracks that answers pages as Jellyfin does, at most [cap] per page.
JellyfinClient _library(int count, {int cap = 1 << 30, List<int>? starts}) => JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async {
        final start = int.parse(r.url.queryParameters['startIndex']!);
        final limit = int.parse(r.url.queryParameters['limit']!);
        starts?.add(start);
        final end = (start + (limit < cap ? limit : cap)).clamp(0, count);
        final items = [
          for (var i = start; i < end; i++) {'Id': 't$i', 'Name': 'Track $i', 'Type': 'Audio'},
        ];
        return http.Response(jsonEncode({'Items': items, 'TotalRecordCount': count}), 200);
      }),
    );

void main() {
  group('a big library', () {
    test('comes whole, in order, without repeats, several pages at a time', () async {
      final starts = <int>[];
      final progress = <int>[];
      final tracks = await _library(9500, starts: starts).musicTracks('lib', progress: (loaded, _) => progress.add(loaded));
      expect(tracks.length, 9500);
      expect(tracks.first.id, 't0');
      expect(tracks.last.id, 't9499');
      expect(tracks.map((t) => t.id).toSet().length, 9500);
      // The first page, then the other four at once.
      expect(starts, [0, 2000, 4000, 6000, 8000]);
      expect(progress, [2000, 9500]);
    });

    test('a server that sends fewer per page than asked still gives everything', () async {
      final tracks = await _library(2500, cap: 1000).musicTracks('lib');
      expect([for (final t in tracks) t.id], [for (var i = 0; i < 2500; i++) 't$i']);
    });

    test('an empty library is an empty list', () async {
      expect(await _library(0).musicTracks('lib'), isEmpty);
    });
  });

  group('the copy on the phone', () {
    test('keeps the server records as they came', () {
      final records = [
        {'Id': 't1', 'Name': 'One', 'Album': 'A', 'UserData': {'IsFavorite': true}},
        {'Id': 't2', 'Name': 'Two'},
      ];
      final back = decodeTracks(encodeTracks(records, DateTime(2026, 10, 31)));
      expect(back, records);
      expect(JellyfinItem(back!.first).isFavorite, isTrue);
    });

    test('a damaged file or one of another layout is not used', () {
      expect(decodeTracks('not json'), isNull);
      expect(decodeTracks('{"v":99,"items":[]}'), isNull);
      expect(decodeTracks('{"v":1,"items":[]}'), isNull, reason: 'an older layout');
      expect(decodeTracks('{"v":2}'), isNull);
      expect(decodeTracks('{"v":2,"items":[{"Name":"no id"},{"Id":"ok"}]}'), [
        {'Id': 'ok'}
      ]);
    });

    test('keeps only what the app reads of a record', () {
      final slim = slimTrack({
        'Id': 't1',
        'Name': 'One',
        'UserData': {'PlayCount': 3},
        'ImageBlurHashes': {'Primary': {'abc': 'LKO2?U%2Tw=w]~RBVZRi};RPxuwH'}},
        'ServerId': 's',
        'ArtistItems': [{'Name': 'A', 'Id': 'a'}],
        'Album': null,
      });
      expect(slim, {'Id': 't1', 'Name': 'One', 'UserData': {'PlayCount': 3}});
      expect(JellyfinItem(slim).playCount, 3);
    });

    test('a folder per server and user, a file per library', () {
      String key(String user, String library) => LibraryCache.key(baseUrl: 'http://nas:8096', userId: user, libraryId: library);
      final a = key('me', 'music');
      expect(a, key('me', 'music'));
      expect(a, matches(RegExp(r'^[0-9a-f]{40}/[0-9a-f]{40}$')));
      // Another library of the same person: the same folder, so removing the server removes both.
      expect(key('me', 'other').split('/').first, a.split('/').first);
      expect(key('me', 'other'), isNot(a));
      expect(key('friend', 'music').split('/').first, isNot(a.split('/').first));
    });
  });
}
