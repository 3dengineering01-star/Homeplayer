import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/services/search_filters.dart';
import 'package:homeplay/services/search_results.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _account = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'me');

void main() {
  final now = DateTime(2026, 10, 7);

  test('words, kind, years, genres and watched become the server query', () {
    const f = SearchFilters(
      text: '  dune ',
      kind: SearchKind.movies,
      fromYear: 1984,
      toYear: 1986,
      genres: {'Science Fiction', 'Adventure'},
      watched: Watched.unwatched,
    );
    final q = f.itemsQuery('me', now: now);
    expect(q['searchTerm'], 'dune');
    expect(q['includeItemTypes'], 'Movie');
    expect(q['years'], '1984,1985,1986');
    expect(q['genres'], 'Science Fiction|Adventure');
    expect(q['isPlayed'], 'false');
    expect(q.containsKey('sortBy'), isFalse, reason: 'best match keeps the server order');
    expect(f.extraFilters, 3);
  });

  test('an open year range ends this year or starts in 1900, and is kept short', () {
    expect(const SearchFilters(fromYear: 2024).years(now: now), [2024, 2025, 2026]);
    expect(const SearchFilters(toYear: 1901).years(now: now), [1900, 1901]);
    expect(const SearchFilters(fromYear: 1800, toYear: 2000).years(now: now).first, 1850);
    expect(const SearchFilters(fromYear: 2000, toYear: 1990).years(now: now), isEmpty);
  });

  test('without words the results are sorted by name, unless another order is picked', () {
    expect(const SearchFilters(kind: SearchKind.movies).itemsQuery('me')['sortBy'], 'SortName');
    final newest = const SearchFilters(sort: SearchSort.newest).itemsQuery('me');
    expect(newest['sortBy'], startsWith('ProductionYear'));
    expect(newest['sortOrder'], 'Descending');
  });

  test('nothing is asked before there is something to look for; artists need a name', () {
    expect(const SearchFilters().isReady, isFalse);
    expect(const SearchFilters(text: ' ').isReady, isFalse);
    expect(const SearchFilters(kind: SearchKind.movies).isReady, isTrue);
    expect(const SearchFilters(watched: Watched.watched).isReady, isTrue);
    expect(const SearchFilters(text: 'abba').wantsArtists, isTrue);
    expect(const SearchFilters(text: 'abba', fromYear: 1970).wantsArtists, isFalse);
    expect(const SearchFilters(kind: SearchKind.artists).wantsArtists, isFalse);
  });

  test('copyWith can clear a year', () {
    const f = SearchFilters(fromYear: 1990);
    expect(f.copyWith(fromYear: () => null).fromYear, isNull);
    expect(f.copyWith(text: 'x').fromYear, 1990);
  });

  test('recent searches: newest first, no repeats, ten at most', () {
    var r = <String>[];
    for (var i = 0; i < 12; i++) {
      r = rememberSearch(r, 'q$i');
    }
    expect(r.length, 10);
    expect(r.first, 'q11');
    expect(rememberSearch(['Dune', 'abba'], ' dune ').take(2), ['dune', 'abba']);
    expect(rememberSearch(['a'], '  '), ['a']);
  });

  test('results come in sections by kind, movies first', () {
    JellyfinItem i(String type) => JellyfinItem({'Id': type, 'Name': type, 'Type': type});
    final sections = groupResults([i('Audio'), i('Movie'), i('Folder'), i('MusicArtist'), i('Audio')]);
    expect([for (final (t, items) in sections) '$t:${items.length}'], ['Movies:1', 'Artists:1', 'Tracks:2', 'Other:1']);
  });

  test('a search asks /Items and, for a name, /Artists', () async {
    final seen = <String>[];
    final c = JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async {
        seen.add(r.url.path);
        return http.Response(
            jsonEncode({
              'Items': [
                {'Id': r.url.path, 'Name': 'x', 'Type': r.url.path == '/Artists' ? 'MusicArtist' : 'Movie'},
              ],
            }),
            200);
      }),
    );
    final found = await c.search(const SearchFilters(text: 'x'));
    // By name, the artists, and the found artists' tracks and albums (the same item here).
    expect(seen..sort(), ['/Artists', '/Items', '/Items']);
    expect(found.length, 2);
    seen.clear();
    await c.search(const SearchFilters(text: 'x', kind: SearchKind.movies));
    expect(seen, ['/Items']);
  });

  test('tracks and albums are also found by their artist', () async {
    final seen = <Uri>[];
    final c = JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async {
        seen.add(r.url);
        final items = switch (r.url.path) {
          '/Artists' => [
              {'Id': 'dan', 'Name': 'Danheim', 'Type': 'MusicArtist'},
            ],
          _ when r.url.queryParameters.containsKey('artistIds') => [
              {'Id': 'vali', 'Name': 'Vali', 'Type': 'Audio'},
              {'Id': 'same', 'Name': 'Danheim live', 'Type': 'Audio'},
            ],
          _ => [
              {'Id': 'same', 'Name': 'Danheim live', 'Type': 'Audio'},
            ],
        };
        return http.Response(jsonEncode({'Items': items}), 200);
      }),
    );
    final found = await c.search(const SearchFilters(text: 'danheim', kind: SearchKind.tracks));
    expect([for (final i in found) i.id], ['same', 'vali'], reason: 'no artist row for Tracks, no doubles');
    final byArtist = seen.firstWhere((u) => u.queryParameters.containsKey('artistIds'));
    expect(byArtist.queryParameters['artistIds'], 'dan');
    expect(byArtist.queryParameters['includeItemTypes'], 'Audio');
    expect(const SearchFilters(text: 'x', kind: SearchKind.albums).itemsQuery('me')['isMissing'], 'false');
    expect(const SearchFilters(text: 'x', kind: SearchKind.movies).byArtist, isFalse);
  });

  test('albums come from the tracks: on their own tab always, with All only for words', () {
    expect(const SearchFilters(kind: SearchKind.albums).wantsAlbums, isTrue);
    expect(const SearchFilters(kind: SearchKind.albums).isReady, isTrue);
    expect(const SearchFilters(text: 'bell').wantsAlbums, isTrue);
    expect(const SearchFilters().wantsAlbums, isFalse);
    expect(const SearchFilters(kind: SearchKind.tracks, text: 'bell').wantsAlbums, isFalse);
    expect(SearchKind.all.types, isNot(contains('MusicAlbum')));
  });
}
