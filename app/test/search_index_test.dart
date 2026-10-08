import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/services/search_filters.dart';
import 'package:homeplay/services/search_index.dart';

JellyfinItem file(String id, String type, String path, {String? name, String? album, String? albumId, String? artist}) =>
    JellyfinItem({
      'Id': id,
      'Type': type,
      'Name': name ?? path.split(RegExp(r'[/\\]')).last.split('.').first,
      'Path': path,
      'Album': ?album,
      'AlbumId': ?albumId,
      'AlbumArtist': ?artist,
      'Artists': [?artist],
    });

final _cluster = file('c1', 'Audio', r'D:\Music\Bell\01-Cluster One.mp3',
    name: 'Cluster One', album: 'The Division Bell', albumId: 'bell', artist: 'Pink Floyd');
final _poles = file('c2', 'Audio', r'D:\Music\Bell\03-Poles Apart.mp3',
    name: 'Poles Apart', album: 'The Division Bell', albumId: 'bell', artist: 'Pink Floyd');
final _gripir = file('g', 'Audio', r'D:\Music\Danheim\Mannavegr\01 Gripir.flac',
    name: 'Gripir', album: 'Mannavegr', albumId: 'm', artist: 'Danheim');
final _vessels = file('v', 'Movie', r'D:\Movies\H264 AAC\Vessels.mp4');
final _photo = file('p', 'Photo', r'D:\Foto\2026-10\PXL_20261006_101.jpg');
final _road = JellyfinItem({'Id': 'pl', 'Name': 'Road trip', 'Type': 'Playlist'});

SearchIndex _index() => SearchIndex([_cluster, _poles, _gripir, _vessels, _photo], [
      (playlist: _road, items: [_gripir, _cluster]),
    ]);

void main() {
  test('a track is found itself and in its album, folder and playlist', () {
    final hits = _index().find('cluster', SearchKind.all);
    expect([for (final i in hits.items) i.id], ['c1']);
    expect(hits.albums.single.group.name, 'The Division Bell');
    expect([for (final i in hits.albums.single.inside) i.name], ['Cluster One']);
    expect(hits.folders.single.group.name, 'Bell');
    expect(hits.folders.single.inside.single.id, 'c1');
    expect(hits.playlists.single.group.name, 'Road trip');
    expect(hits.playlists.single.inside.single.id, 'c1');
  });

  test('groups found by their own name list nothing inside', () {
    final hits = _index().find('road', SearchKind.all);
    expect(hits.playlists.single.inside, isEmpty);
    expect(hits.items, isEmpty);
    final bell = _index().find('division bell', SearchKind.all);
    expect(bell.albums.single.inside, isEmpty, reason: 'the album name itself matches');
    expect(bell.items.length, 2, reason: 'both tracks carry the album name');
  });

  test('each kind keeps to itself; albums and folders list all without words', () {
    final index = _index();
    expect(index.find('cluster', SearchKind.tracks).albums, isEmpty);
    expect(index.find('cluster', SearchKind.tracks).items.single.id, 'c1');
    expect(index.find('cluster', SearchKind.movies).isEmpty, isTrue);
    expect(index.find('pxl', SearchKind.photos).items.single.id, 'p');
    expect(index.find('2026 10', SearchKind.folders).folders.single.group.name, '2026-10');
    expect(index.find('', SearchKind.albums).albums.length, 2);
    expect(index.find('', SearchKind.folders).folders.length, 4);
    expect(index.find('', SearchKind.all).isEmpty, isTrue);
  });

  test('file names count, with dots, dashes and underscores as spaces', () {
    final index = _index();
    expect(index.find('01-cluster', SearchKind.all).items.single.id, 'c1');
    expect(index.find('vessels.mp4', SearchKind.all).items.single.id, 'v');
    expect(foundByFileName(_cluster, '01 cluster'), isTrue);
    expect(foundByFileName(_cluster, 'cluster'), isFalse, reason: 'the title says it already');
    expect(foundByFileName(_cluster, 'floyd'), isFalse);
  });

  test('typed words are marked where they are, case and separators aside', () {
    expect(highlightRanges('Cluster One', 'clu one'), [(0, 3), (8, 11)]);
    expect(highlightRanges('01-Cluster_One.mp3', 'cluster one'), [(3, 10), (11, 14)]);
    expect(highlightRanges('Poles Apart', 'xyz'), isEmpty);
    expect(highlightRanges('aaa', 'aa a'), [(0, 3)], reason: 'overlaps merge');
  });

  test('files are grouped by the folder they lie in', () {
    final folders = groupByFolder([_cluster, _poles, _gripir, JellyfinItem({'Id': 'x', 'Name': 'no path'})]);
    expect([for (final f in folders) '${f.name}:${f.items.length}'], ['Bell:2', 'Mannavegr:1']);
    expect(folders.first.path, r'D:\Music\Bell');
  });

  test('a dashed or dotted piece is looked for whole, not as separate numbers', () {
    expect(queryWords('2026-10  pxl'), ['2026 10', 'pxl']);
    final index = SearchIndex([
      file('a', 'Photo', r'D:\Foto\2026-09\PXL_20260907_101738138.jpg'),
      file('b', 'Photo', r'D:\Foto\2026-10\PXL_20261006_1.jpg'),
    ], const []);
    final hits = index.find('2026-10', SearchKind.all);
    expect([for (final f in hits.folders) f.group.name], ['2026-10']);
    expect(hits.items, isEmpty, reason: 'no file name has "2026 10" in it');
    expect(index.find('pxl_2026', SearchKind.all).items.length, 2);
  });

  test('an artist is found by name or by a track of theirs', () {
    final byTrack = _index().find('cluster', SearchKind.all).artists.single;
    expect(byTrack.group.name, 'Pink Floyd');
    expect(byTrack.inside.single.name, 'Cluster One');
    expect(_index().find('floyd', SearchKind.artists).artists.single.inside, isEmpty);
    expect(_index().find('cluster', SearchKind.tracks).artists, isEmpty);
  });
}
