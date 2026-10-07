import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/services/music_index.dart';

JellyfinItem track(String name,
        {String? album, String? albumId, String? albumArtist, List<String> artists = const [], int? n, int? disc, int? year, String? added, int seconds = 200}) =>
    JellyfinItem({
      'Id': name,
      'Name': name,
      'Type': 'Audio',
      'Album': ?album,
      'AlbumId': ?albumId,
      'AlbumArtist': ?albumArtist,
      'Artists': artists,
      'IndexNumber': ?n,
      'ParentIndexNumber': ?disc,
      'ProductionYear': ?year,
      'DateCreated': ?added,
      'RunTimeTicks': seconds * 10000000,
    });

final _library = [
  track('Gripir', album: 'Mannavegr', albumId: 'm', albumArtist: 'Danheim', n: 2, year: 2018, added: '2026-10-01T00:00:00Z'),
  track('Vali', album: 'Mannavegr', albumId: 'm', albumArtist: 'Danheim', n: 1, year: 2018, added: '2026-10-02T00:00:00Z'),
  track('Kala', album: 'Skapanir', albumId: 's', albumArtist: 'Danheim', n: 1, year: 2017),
  track('Time', artists: ['Pink Floyd'], seconds: 413),
  track('Money', artists: [' Pink Floyd '], seconds: 382),
  track('Poles Apart', album: 'The Division Bell', artists: ['Pink Floyd'], n: 2, disc: 1, year: 1994),
  track('Cluster One', album: 'The Division Bell', artists: ['Pink Floyd'], n: 1, disc: 1, year: 1994),
  track('Loose', artists: const []),
];

void main() {
  test('tracks go into albums by the server id, by name, or as other tracks of their artist', () {
    final albums = groupByAlbum(_library);
    final names = [for (final a in albums) '${a.name}/${a.artist}/${a.tracks.map((t) => t.name).join(',')}'];
    expect(names, [
      'Mannavegr/Danheim/Vali,Gripir',
      'Other tracks/Pink Floyd/Money,Time',
      'Other tracks/Unknown artist/Loose',
      'Skapanir/Danheim/Kala',
      'The Division Bell/Pink Floyd/Cluster One,Poles Apart',
    ]);
    final bell = albums.last;
    expect(bell.albumId, isNull, reason: 'grouped by name, no server album');
    expect(albums.first.albumId, 'm');
    expect(albums.first.year, 2018);
    expect(albums.first.added, DateTime.utc(2026, 10, 2));
    expect(albums[1].loose, isTrue);
  });

  test('artists hold their albums oldest first, loose tracks last', () {
    final artists = groupByArtist(_library);
    expect([for (final a in artists) a.name], ['Danheim', 'Pink Floyd', 'Unknown artist']);
    final floyd = artists[1];
    expect([for (final a in floyd.albums) a.name], ['The Division Bell', 'Other tracks']);
    expect(floyd.trackCount, 4);
    expect([for (final a in artists.first.albums) a.name], ['Skapanir', 'Mannavegr']);
    expect(sortArtists(artists, ArtistSort.tracks).first.name, 'Pink Floyd');
  });

  test('a compilation without an album artist is by various artists', () {
    final albums = groupByAlbum([
      track('A', album: 'Hits', albumId: 'h', artists: ['One']),
      track('B', album: 'Hits', albumId: 'h', artists: ['Two']),
    ]);
    expect(albums.single.artist, 'Various artists');
  });

  test('tracks sort by title, artist, album, date added and length', () {
    List<String> by(TrackSort s) => [for (final t in sortTracks(_library, s)) t.name];
    expect(by(TrackSort.title).take(3), ['Cluster One', 'Gripir', 'Kala']);
    expect(by(TrackSort.artist).take(3), ['Vali', 'Gripir', 'Kala']);
    expect(by(TrackSort.added).take(2), ['Vali', 'Gripir']);
    expect(by(TrackSort.length).first, 'Time');
    expect(by(TrackSort.album).first, 'Vali');
    expect(by(TrackSort.album).last, isIn(['Loose', 'Money', 'Time']));
  });

  test('albums sort by name, artist, year and date added', () {
    final albums = groupByAlbum(_library);
    expect(sortAlbums(albums, AlbumSort.year).first.name, 'Mannavegr');
    expect(sortAlbums(albums, AlbumSort.added).first.name, 'Mannavegr');
    expect(sortAlbums(albums, AlbumSort.artist).first.artist, 'Danheim');
  });

  test('the filter matches every word in the name, artist or album', () {
    expect(trackMatches(_library.first, 'danheim grip'), isTrue);
    expect(trackMatches(_library.first, 'mannavegr'), isTrue);
    expect(trackMatches(_library.first, 'floyd'), isFalse);
    expect(trackMatches(_library[4], 'pink money'), isTrue);
  });

  test('without a track tag the number at the start of the file name orders the album', () {
    expect(trackNumberFromPath(r'D:\Music\The Division Bell\01-Cluster One.mp3'), 1);
    expect(trackNumberFromPath('/music/3. Time.flac'), 3);
    expect(trackNumberFromPath('/music/11 High Hopes.mp3'), 11);
    expect(trackNumberFromPath('/music/1994 Live.mp3'), isNull, reason: 'a year, not a track number');
    expect(trackNumberFromPath('/music/Money.mp3'), isNull);
    expect(trackNumberFromPath(null), isNull);
    JellyfinItem file(String name) => JellyfinItem({'Id': name, 'Name': name.substring(3), 'Type': 'Audio', 'Path': 'D:\\x\\$name.mp3'});
    final ordered = [file('07-A Great Day'), file('01-Cluster One'), file('11-High Hopes')]..sort(albumOrder);
    expect([for (final t in ordered) t.name], ['Cluster One', 'A Great Day', 'High Hopes']);
  });

  test('albums are found by name or artist, all of them for no words, loose tracks never', () {
    final albums = groupByAlbum(_library);
    expect([for (final a in findAlbums(albums, 'danheim')) a.name], ['Mannavegr', 'Skapanir']);
    expect([for (final a in findAlbums(albums, 'bell pink')) a.name], ['The Division Bell']);
    expect(findAlbums(albums, '').length, 3);
    expect([for (final a in findAlbums(albums, '', from: 2018)) a.name], ['Mannavegr']);
  });
}
