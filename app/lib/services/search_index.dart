import '../api/jellyfin.dart';
import 'music_index.dart';
import 'search_filters.dart';

// Everything on the server the search can find without asking it again: every file (videos,
// tracks, photos) with its name on disk, the albums and folders they make, and the playlists
// with what is in them. Built once, then searched on the phone with every letter typed.

/// Lowercase, with dots, dashes and underscores as spaces: "01-Cluster_One" reads "01 cluster one".
/// One character for one, so places found in it are places in the original text.
String plainText(String s) => s.toLowerCase().replaceAll(RegExp(r'[._\-]'), ' ');

/// The words of a query, split at spaces only: "2026-10" stays one piece ("2026 10") that has to
/// be found as it is, so it does not match a "10" somewhere else in a name.
List<String> queryWords(String query) => [
  for (final w in query.split(RegExp(r'\s+')))
    if (plainText(w).trim() case final piece when piece.isNotEmpty) piece,
];

bool _hasAll(String text, List<String> words) {
  final t = plainText(text);
  return words.every(t.contains);
}

/// An item's own words: its title, performers, album and series.
String titleText(JellyfinItem i) => [i.name, ...i.artists, i.albumArtist ?? '', i.album ?? '', i.seriesName ?? ''].join(' ');

/// What an item is found by: its own words and its file name.
String itemText(JellyfinItem i) => '${titleText(i)} ${i.fileName ?? ''}';

bool itemMatches(JellyfinItem i, List<String> words) => words.isNotEmpty && _hasAll(itemText(i), words);

/// Whether [text] has every one of [words].
bool textMatches(String text, List<String> words) => words.isNotEmpty && _hasAll(text, words);

/// Found by [query] only thanks to the file name: then the file name is worth showing.
bool foundByFileName(JellyfinItem i, String query) {
  final words = queryWords(query);
  return i.fileName != null && itemMatches(i, words) && !_hasAll(titleText(i), words);
}

/// Where the query's words are in [text], as start and end, merged where they touch.
List<(int, int)> highlightRanges(String text, String query) {
  final t = plainText(text);
  final ranges = <(int, int)>[];
  for (final w in queryWords(query)) {
    for (var at = t.indexOf(w); at >= 0; at = t.indexOf(w, at + w.length)) {
      ranges.add((at, at + w.length));
    }
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in ranges) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// A folder on the server's disk and the files in it.
class FolderGroup {
  FolderGroup(this.path, this.items);

  final String path;
  final List<JellyfinItem> items;

  String get name => path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).lastOrNull ?? path;
}

/// Files by the folder they lie in, by folder name.
List<FolderGroup> groupByFolder(List<JellyfinItem> files) {
  final byPath = <String, List<JellyfinItem>>{};
  for (final f in files) {
    final path = f.path;
    if (path == null) continue;
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    if (cut <= 0) continue;
    (byPath[path.substring(0, cut)] ??= []).add(f);
  }
  return [
    for (final MapEntry(key: path, value: items) in byPath.entries)
      FolderGroup(path, items..sort((a, b) => (a.fileName ?? a.name).toLowerCase().compareTo((b.fileName ?? b.name).toLowerCase()))),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// A group found by its own name ([inside] empty), or because of what is in it.
class Hit<T> {
  Hit(this.group, this.inside);

  final T group;

  /// The matching items in it, when the group's own name does not match.
  final List<JellyfinItem> inside;
}

/// A playlist and what is in it.
typedef PlaylistContents = ({JellyfinItem playlist, List<JellyfinItem> items});

class LocalHits {
  const LocalHits({
    this.items = const [],
    this.artists = const [],
    this.albums = const [],
    this.folders = const [],
    this.playlists = const [],
  });

  final List<JellyfinItem> items;
  final List<Hit<ArtistGroup>> artists;
  final List<Hit<AlbumGroup>> albums;
  final List<Hit<FolderGroup>> folders;
  final List<Hit<JellyfinItem>> playlists;

  bool get isEmpty => items.isEmpty && artists.isEmpty && albums.isEmpty && folders.isEmpty && playlists.isEmpty;
}

class SearchIndex {
  SearchIndex(this.files, this.playlists)
      : artists = groupByArtist(files.where((f) => f.type == 'Audio').toList()),
        albums = groupByAlbum(files.where((f) => f.type == 'Audio').toList()).where((a) => !a.loose).toList(),
        folders = groupByFolder(files);

  final List<JellyfinItem> files;
  final List<PlaylistContents> playlists;
  final List<ArtistGroup> artists;
  final List<AlbumGroup> albums;
  final List<FolderGroup> folders;

  /// What [query] finds of [kind]: the files themselves, and the artists, albums, folders and
  /// playlists named so or holding a file that is. With no words, a kind of its own (albums,
  /// folders) lists everything.
  LocalHits find(String query, SearchKind kind) {
    final words = queryWords(query);
    final all = kind == SearchKind.all;
    if (words.isEmpty) {
      return switch (kind) {
        SearchKind.albums => LocalHits(albums: [for (final a in albums) Hit(a, const [])]),
        SearchKind.folders => LocalHits(folders: [for (final f in folders) Hit(f, const [])]),
        _ => const LocalHits(),
      };
    }
    final matched = {for (final f in files) if (itemMatches(f, words)) f.id};
    final types = kind.types?.split(',').toSet();
    List<JellyfinItem> inside(List<JellyfinItem> items) => [for (final i in items) if (matched.contains(i.id)) i];
    Hit<T>? hit<T>(T group, String name, List<JellyfinItem> items) {
      if (_hasAll(name, words)) return Hit(group, const []);
      final found = inside(items);
      return found.isEmpty ? null : Hit(group, found);
    }

    return LocalHits(
      items: types == null ? const [] : [for (final f in files) if (matched.contains(f.id) && types.contains(f.type)) f],
      artists: all || kind == SearchKind.artists ? [for (final a in artists) ?hit(a, a.name, a.tracks)] : const [],
      albums: all || kind == SearchKind.albums
          ? [for (final a in albums) ?hit(a, '${a.name} ${a.artist}', a.tracks)]
          : const [],
      folders: all || kind == SearchKind.folders ? [for (final f in folders) ?hit(f, f.name, f.items)] : const [],
      playlists: all || kind == SearchKind.playlists
          ? [for (final p in playlists) ?hit(p.playlist, p.playlist.name, p.items)]
          : const [],
    );
  }
}

/// What a query finds on the music screen, in the order given: artists and albums named so or
/// holding a matching track, and the tracks themselves (by title, artist, album or file name).
typedef MusicHits = ({List<Hit<ArtistGroup>> artists, List<Hit<AlbumGroup>> albums, List<JellyfinItem> tracks});

MusicHits findInMusic(List<ArtistGroup> artists, List<AlbumGroup> albums, List<JellyfinItem> tracks, String query) {
  final words = queryWords(query);
  if (words.isEmpty) {
    return (
      artists: [for (final a in artists) Hit(a, const [])],
      albums: [for (final a in albums) Hit(a, const [])],
      tracks: tracks,
    );
  }
  final found = [for (final t in tracks) if (itemMatches(t, words)) t];
  final ids = {for (final t in found) t.id};
  Hit<T>? hit<T>(T group, String name, List<JellyfinItem> inside) {
    if (_hasAll(name, words)) return Hit(group, const []);
    final has = [for (final t in inside) if (ids.contains(t.id)) t];
    return has.isEmpty ? null : Hit(group, has);
  }

  return (
    artists: [for (final a in artists) ?hit(a, a.name, a.tracks)],
    albums: [for (final a in albums) ?hit(a, '${a.name} ${a.artist}', a.tracks)],
    tracks: found,
  );
}

/// Playlists named so or holding a matching item; all of them for no words.
List<Hit<JellyfinItem>> findPlaylists(List<PlaylistContents> playlists, String query) {
  final words = queryWords(query);
  return [
    for (final p in playlists)
      if (words.isEmpty || _hasAll(p.playlist.name, words))
        Hit(p.playlist, const [])
      else if ([for (final i in p.items) if (itemMatches(i, words)) i] case final has when has.isNotEmpty)
        Hit(p.playlist, has),
  ];
}
