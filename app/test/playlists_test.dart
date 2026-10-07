import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _account = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'me');

void main() {
  late List<http.Request> seen;
  late JellyfinClient c;

  setUp(() {
    seen = [];
    c = JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async {
        seen.add(r);
        if (r.method == 'POST' && r.url.path == '/Playlists') return http.Response(jsonEncode({'Id': 'new'}), 200);
        if (r.url.path == '/Playlists/p/Items' && r.method == 'GET') {
          return http.Response(
              jsonEncode({
                'Items': [
                  {'Id': 't1', 'Name': 'Vali', 'Type': 'Audio', 'PlaylistItemId': 'e1'},
                ],
              }),
              200);
        }
        return http.Response('', 204);
      }),
    );
  });

  test('a new playlist is made with its tracks and the user', () async {
    expect(await c.createPlaylist('Road', ['t1', 't2']), 'new');
    final r = seen.single;
    expect(r.method, 'POST');
    expect(r.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(r.body), {'Name': 'Road', 'Ids': ['t1', 't2'], 'UserId': 'me', 'MediaType': 'Audio'});
  });

  test('tracks are added by id and taken out by their playlist entry', () async {
    await c.addToPlaylist('p', ['t1', 't2']);
    await c.removeFromPlaylist('p', ['e1']);
    await c.deletePlaylist('p');
    expect(seen[0].method, 'POST');
    expect(seen[0].url.queryParameters['ids'], 't1,t2');
    expect(seen[1].method, 'DELETE');
    expect(seen[1].url.path, '/Playlists/p/Items');
    expect(seen[1].url.queryParameters['entryIds'], 'e1');
    expect(seen[2].method, 'DELETE');
    expect(seen[2].url.path, '/Items/p');
  });

  test('playlist entries carry the id needed to take them out', () async {
    final items = await c.playlistItems('p');
    expect(items.single.playlistEntryId, 'e1');
  });

  test('a refusal reads as advice', () async {
    final refusing = JellyfinClient(_account, 'dev', client: MockClient((_) async => http.Response('', 403)));
    expect(() => refusing.deletePlaylist('p'), throwsA(isA<Exception>()));
  });

  test('all tracks of a library come page by page', () async {
    var asked = 0;
    final paged = JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async {
        asked++;
        final start = int.parse(r.url.queryParameters['startIndex']!);
        final items = [
          for (var i = start; i < (start + 2).clamp(0, 3); i++) {'Id': '$i', 'Name': 't$i', 'Type': 'Audio'},
        ];
        return http.Response(jsonEncode({'Items': items, 'TotalRecordCount': 3}), 200);
      }),
    );
    // A page of 2000 holds everything here; the loop stops on the total.
    final all = await paged.musicTracks('lib');
    expect(all.length, 3);
    expect(asked, 2);
  });
}
