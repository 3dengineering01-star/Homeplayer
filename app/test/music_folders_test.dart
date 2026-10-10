import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/services/music_folders.dart';

JellyfinItem track(String id, String? path, {String? name}) =>
    JellyfinItem({'Id': id, 'Name': name ?? id, 'Type': 'Audio', 'Path': ?path});

void main() {
  test('the folders on disk, from the library folder down: styles, artists, albums', () {
    final root = buildMusicFolders([
      track('a', r'D:\Music\Rock\Pink Floyd\The Division Bell\02-What Do You Want.mp3'),
      track('b', r'D:\Music\Rock\Pink Floyd\The Division Bell\01-Cluster One.mp3'),
      track('c', r'D:\Music\Folk\Danheim\Mannavegr\01 Gripir.flac'),
      track('d', r'D:\Music\folk loose.mp3'),
      track('e', r'D:\Music\Rock\Pink Floyd\single.mp3'),
    ]);
    expect(root.name, 'Music');
    expect(root.path, '');
    expect(root.folders.map((f) => f.name), ['Folk', 'Rock']);
    expect(root.tracks.map((t) => t.id), ['d']);
    expect(root.trackCount, 5);
    final floyd = root.folders[1].folders.single;
    expect(floyd.path, 'Rock/Pink Floyd');
    expect(floyd.tracks.map((t) => t.id), ['e']);
    final bell = floyd.folders.single;
    expect(bell.name, 'The Division Bell');
    expect(bell.tracks.map((t) => t.id), ['b', 'a'], reason: 'by file name, as on disk');
    expect(root.folders[1].allTracks.map((t) => t.id), ['e', 'b', 'a']);
  });

  test('one folder for everything: its tracks are the root; no path: in the root too', () {
    final root = buildMusicFolders([
      track('a', '/srv/music/album/2.mp3'),
      track('b', '/srv/music/album/1.mp3'),
      track('c', null),
    ]);
    expect(root.name, 'album');
    expect(root.folders, isEmpty);
    expect(root.tracks.map((t) => t.id), ['b', 'a', 'c'], reason: 'by file name; without one, by name');
    expect(buildMusicFolders([]).trackCount, 0);
  });

  test('search finds folders by name or by a track in them, at any depth', () {
    final root = buildMusicFolders([
      track('a', r'D:\Music\Rock\Pink Floyd\The Division Bell\01-Cluster One.mp3', name: 'Cluster One'),
      track('c', r'D:\Music\Folk\Danheim\Mannavegr\01 Gripir.flac', name: 'Gripir'),
    ]);
    expect(findFolders(root, '').length, 0);
    final floyd = findFolders(root, 'floyd');
    expect(floyd.map((h) => h.group.name), ['Pink Floyd']);
    expect(floyd.single.inside, isEmpty);
    final gripir = findFolders(root, 'gripir');
    expect(gripir.map((h) => h.group.name), ['Mannavegr']);
    expect(gripir.single.inside.single.id, 'c');
  });
}
