import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/accounts_screen.dart';
import 'package:homeplay/widgets/library_tiles.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _account = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'me');

JellyfinClient server(Object Function(http.Request r) answer, {List<http.Request>? seen}) => JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async {
        seen?.add(r);
        return http.Response(jsonEncode(answer(r)), 200);
      }),
    );

void main() {
  test('latest reads a bare list, resume and next up read {Items}', () async {
    final seen = <http.Request>[];
    final c = server((r) => r.url.path == '/Items/Latest'
        ? [
            {'Id': '1', 'Name': 'Dune', 'Type': 'Movie'},
          ]
        : {
            'Items': [
              {'Id': '2', 'Name': 'Pilot', 'Type': 'Episode'},
            ],
          }, seen: seen);
    expect((await c.latest('lib')).single.name, 'Dune');
    expect((await c.resume()).single.name, 'Pilot');
    expect((await c.nextUp()).single.name, 'Pilot');
    expect(seen[0].url.queryParameters['parentId'], 'lib');
    expect(seen[1].url.path, '/UserItems/Resume');
    expect(seen[1].url.queryParameters['mediaTypes'], 'Video');
    expect(seen[2].url.path, '/Shows/NextUp');
    expect(seen.every((r) => r.url.queryParameters['userId'] == 'me'), isTrue);
  });

  test('a library page asks for its type and order and reads the total', () async {
    final seen = <http.Request>[];
    final c = server((r) => {
          'Items': [
            {'Id': '1', 'Name': 'A'},
            {'Id': '2', 'Name': 'Ghost', 'LocationType': 'Virtual'},
          ],
          'TotalRecordCount': 250,
        }, seen: seen);
    final page = await c.libraryPage('lib', types: 'Movie', sort: LibrarySort.added, start: 60);
    expect(page.total, 250);
    expect(page.items.map((i) => i.name), ['A']);
    final q = seen.single.url.queryParameters;
    expect(q['includeItemTypes'], 'Movie');
    expect(q['sortBy'], 'DateCreated,SortName');
    expect(q['sortOrder'], 'Descending');
    expect(q['startIndex'], '60');
    expect(q['recursive'], 'true');
  });

  test('details read like a movie page', () {
    final m = JellyfinItem({
      'Id': 'm',
      'Name': 'Dune ',
      'Type': 'Movie',
      'Overview': ' A desert planet. ',
      'ProductionYear': 2021,
      'RunTimeTicks': 93600000000, // 2 h 36 min
      'CommunityRating': 7.8,
      'OfficialRating': 'PG-13',
      'Genres': ['Science Fiction', 'Adventure'],
      'BackdropImageTags': ['b'],
    });
    expect(m.overview, 'A desert planet.');
    expect(m.year, 2021);
    expect(runTimeLabel(m.runTime!), '2 h 36 min');
    expect(m.rating, 7.8);
    expect(m.ageRating, 'PG-13');
    expect(m.genres, ['Science Fiction', 'Adventure']);
    expect(m.backdropOwner, 'm');
    expect(runTimeLabel(const Duration(minutes: 48)), '48 min');
    expect(runTimeLabel(const Duration(hours: 2)), '2 h');
    expect(runTimeLabel(const Duration(seconds: 20)), '20 s');
  });

  test('an episode without its own backdrop uses the series picture; its card shows its still', () {
    final c = server((_) => {});
    final e = JellyfinItem({
      'Id': 'e',
      'Type': 'Episode',
      'ParentBackdropItemId': 'series',
      'ImageTags': {'Primary': 'p'},
      'UserData': {'UnplayedItemCount': 3},
    });
    expect(e.backdropOwner, 'series');
    expect(c.backdropUrl(e)!.path, '/Items/series/Images/Backdrop');
    expect(c.wideUrl(e)!.path, '/Items/e/Images/Primary');
    expect(e.unwatched, 3);
    expect(c.backdropUrl(JellyfinItem({'Id': 'x'})), isNull);
  });

  test('libraries get poster grids by kind, others stay folders', () {
    expect(posterTypes('movies'), 'Movie');
    expect(posterTypes('tvshows'), 'Series');
    expect(posterTypes('music'), 'MusicAlbum');
    expect(posterTypes('homevideos'), isNull);
    expect(posterTypes(null), isNull);
  });

  test('a library count asks for no items, only the total', () async {
    final seen = <http.Request>[];
    final c = server((_) => {'Items': [], 'TotalRecordCount': 124}, seen: seen);
    expect(await c.count('lib', 'Movie'), 124);
    final q = seen.single.url.queryParameters;
    expect(q['parentId'], 'lib');
    expect(q['includeItemTypes'], 'Movie');
    expect(q['limit'], '0');
    expect(q['recursive'], 'true');
  });

  test('library tiles say what is inside in plain words', () {
    expect(countLabel(124, libraryKind('movies')), '124 movies');
    expect(countLabel(1, libraryKind('tvshows')), '1 show');
    expect(countLabel(0, libraryKind('music')), '0 albums');
    expect(countLabel(37, tracksKind), '37 tracks');
    expect(libraryKind('homevideos').types, 'Video,Photo');
    expect(libraryKind(null).types, isNull);
  });

  test('the app starts on the server opened last, or the only one', () {
    const other = Account(
        id: 'b', kind: ServerKind.subsonic, baseUrl: 'http://nas:4533', username: 'u', serverName: 'Music', token: 't');
    expect(pickStartAccount([_account, other], 'b'), other);
    expect(pickStartAccount([_account, other], null), isNull);
    expect(pickStartAccount([_account, other], 'gone'), isNull);
    expect(pickStartAccount([_account], null), _account);
    expect(pickStartAccount([], 'a'), isNull);
  });

  test('a track without its own picture shows its album cover', () {
    final c = server((_) => {});
    final track = JellyfinItem({'Id': 't', 'Type': 'Audio', 'AlbumId': 'al', 'AlbumPrimaryImageTag': 'x'});
    expect(c.imageUrl(track)!.path, '/Items/al/Images/Primary');
    final own = JellyfinItem({'Id': 't', 'Type': 'Audio', 'AlbumId': 'al', 'AlbumPrimaryImageTag': 'x', 'ImageTags': {'Primary': 'p'}});
    expect(c.imageUrl(own)!.path, '/Items/t/Images/Primary');
    expect(c.imageUrl(JellyfinItem({'Id': 't', 'Type': 'Audio', 'AlbumId': 'al'})), isNull);
  });
}
