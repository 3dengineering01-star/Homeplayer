import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/api/subsonic.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/services/car_library.dart';
import 'package:homeplay/services/downloads.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const jf = Account(
    id: 'jf:http://nas:8096:u1', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'anna', serverName: 'NAS', token: 't', userId: 'u1');
const ss = Account(
    id: 'ss:http://music:4533:anna', kind: ServerKind.subsonic, baseUrl: 'http://music:4533', username: 'anna', serverName: 'Navidrome', token: 't', salt: 's');

/// Jellyfin with a music and a movie library; the music has an album folder and a track.
final jellyfinServer = MockClient((r) async {
  Map<String, dynamic> items(List<Map<String, dynamic>> l) => {'Items': l};
  final q = r.url.queryParameters;
  if (r.url.path == '/UserViews') {
    return http.Response(jsonEncode(items([
      {'Id': 'music', 'Name': 'Music', 'CollectionType': 'music', 'IsFolder': true},
      {'Id': 'movies', 'Name': 'Movies', 'CollectionType': 'movies', 'IsFolder': true},
    ])), 200);
  }
  if (q['searchTerm'] == 'floyd') {
    return http.Response(jsonEncode(items([
      {'Id': 't9', 'Name': 'Time', 'MediaType': 'Audio', 'Type': 'Audio', 'Artists': ['Pink Floyd']},
    ])), 200);
  }
  if (q['parentId'] == 'music') {
    return http.Response(jsonEncode(items([
      {'Id': 'al', 'Name': 'The Division Bell', 'Type': 'MusicAlbum', 'IsFolder': true, 'AlbumArtist': 'Pink Floyd'},
      {'Id': 't1', 'Name': 'Cluster One', 'MediaType': 'Audio', 'Type': 'Audio', 'Artists': ['Pink Floyd']},
      {'Id': 't2', 'Name': 'What Do You Want from Me', 'MediaType': 'Audio', 'Type': 'Audio'},
      {'Id': 'v1', 'Name': 'Concert', 'MediaType': 'Video', 'Type': 'Video'},
    ])), 200);
  }
  return http.Response('{}', 404);
});

final subsonicServer = MockClient((r) async {
  Map<String, dynamic> ok(Map<String, dynamic> body) => {
        'subsonic-response': {'status': 'ok', ...body},
      };
  final method = r.url.pathSegments.last;
  final body = switch (method) {
    'getArtists' => ok({
        'artists': {
          'index': [
            {
              'artist': [
                {'id': 'a1', 'name': 'Danheim', 'albumCount': 2},
              ],
            },
          ],
        },
      }),
    'getArtist' => ok({
        'artist': {
          'album': [
            {'id': 'b1', 'name': 'Runes', 'year': 2017},
          ],
        },
      }),
    'getAlbum' => ok({
        'album': {
          'song': [
            {'id': 's1', 'title': 'Kala', 'artist': 'Danheim', 'duration': 240},
            {'id': 's2', 'title': 'Runar', 'artist': 'Danheim', 'duration': 200},
          ],
        },
      }),
    'search3' => ok({
        'searchResult3': {
          'song': [
            {'id': 's2', 'title': 'Runar', 'artist': 'Danheim'},
          ],
        },
      }),
    _ => ok({}),
  };
  return http.Response(jsonEncode(body), 200);
});

CarLibrary library({List<DownloadEntry> downloaded = const [], List<Account> accounts = const [jf, ss]}) => CarLibrary(
      accounts: () async => accounts,
      jellyfin: (a) async => JellyfinClient(a, 'dev', client: jellyfinServer),
      subsonic: (a) => SubsonicClient(a, client: subsonicServer),
      downloads: () async => downloaded,
      downloadedItem: (e) => downloadedPlayItem(e, '/d'),
    );

void main() {
  test('the top level: downloads when there is music, then every server', () async {
    final car = library(downloaded: [const DownloadEntry(id: 'x', title: 'Song', isVideo: false, state: DownloadState.done)]);
    final top = await car.children(CarLibrary.root);
    expect(top.map((i) => i.title), ['Downloads', 'NAS', 'Navidrome']);
    expect(top.every((i) => i.playable == false), isTrue);
    expect((await library().children(CarLibrary.root)).map((i) => i.title), ['NAS', 'Navidrome']);
  });

  test('Jellyfin: music libraries only, folders browse, videos stay out', () async {
    final car = library();
    final server = (await car.children(CarLibrary.root)).firstWhere((i) => i.title == 'NAS');
    final libraries = await car.children(server.id);
    expect(libraries.map((i) => i.title), ['Music']);
    final music = await car.children(libraries.single.id);
    expect(music.map((i) => (i.title, i.playable)), [
      ('The Division Bell', false),
      ('Cluster One', true),
      ('What Do You Want from Me', true),
    ]);
  });

  test('a tapped track plays with the rest of its folder', () async {
    final car = library();
    final server = (await car.children(CarLibrary.root)).firstWhere((i) => i.title == 'NAS');
    final music = await car.children((await car.children(server.id)).single.id);
    final q = car.queueFor(music.last.id)!;
    expect(q.items.map((i) => i.title), ['Cluster One', 'What Do You Want from Me']);
    expect(q.index, 1);
    expect(q.items.first.url.path, '/Audio/t1/stream');
    expect(car.queueFor('jf|never|shown'), isNull);
  });

  test('Subsonic: artists, albums, songs', () async {
    final car = library();
    final server = (await car.children(CarLibrary.root)).firstWhere((i) => i.title == 'Navidrome');
    final artists = await car.children(server.id);
    expect(artists.single.title, 'Danheim');
    final albums = await car.children(artists.single.id);
    expect((albums.single.title, albums.single.artist), ('Runes', '2017'));
    final songs = await car.children(albums.single.id);
    expect(songs.map((s) => s.title), ['Kala', 'Runar']);
    expect(songs.first.duration, const Duration(minutes: 4));
    expect(car.queueFor(songs.first.id)!.items.last.url.queryParameters['id'], 's2');
  });

  test('voice search finds tracks on every server and plays the first', () async {
    final car = library();
    final found = await car.search('floyd');
    expect(found.map((i) => i.title), ['Time', 'Runar']);
    final q = (await car.queueForSearch('floyd'))!;
    expect((q.items.length, q.index), (2, 0));
  });

  test('"play music" without a query plays the downloads', () async {
    final car = library(downloaded: [
      const DownloadEntry(id: 'x', title: 'One', isVideo: false, state: DownloadState.done),
      const DownloadEntry(id: 'y', title: 'Two', isVideo: false, state: DownloadState.done),
    ]);
    final q = (await car.queueForSearch(''))!;
    expect(q.items.map((i) => i.url.toString()), ['file:///d/media_x', 'file:///d/media_y']);
  });

  test('a server that fails says so instead of an empty list', () async {
    final car = CarLibrary(
      accounts: () async => [jf],
      jellyfin: (a) async => JellyfinClient(a, 'dev', client: MockClient((_) async => http.Response('', 500))),
      subsonic: SubsonicClient.new,
      downloads: () async => const [],
      downloadedItem: (e) => throw StateError('unused'),
    );
    final server = (await car.children(CarLibrary.root)).single;
    final shown = await car.children(server.id);
    expect(shown.single.playable, isFalse);
    expect(shown.single.title, contains('500'));
  });

  test('unknown ids list nothing', () async {
    expect(await library().children('jf|${base64Url.encode(utf8.encode('gone'))}|x'), isEmpty);
  });
}
