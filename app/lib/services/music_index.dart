import '../api/jellyfin.dart';

/// A music library's tracks grouped into artists and albums and sorted, from the tracks alone:
/// that works the same whether the server made albums for them or not.

const unknownArtist = 'Unknown artist';

/// The artist a track is filed under: its album's artist, else its first performer.
String artistOf(JellyfinItem t) => t.albumArtist ?? t.artists.firstOrNull ?? unknownArtist;

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Disc, then track number, then name: the order of an album.
int albumOrder(JellyfinItem a, JellyfinItem b) {
  final disc = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
  if (disc != 0) return disc;
  final track = (a.indexNumber ?? 1 << 20).compareTo(b.indexNumber ?? 1 << 20);
  return track != 0 ? track : _byName(a.name, b.name);
}

class AlbumGroup {
  AlbumGroup({required this.key, required this.name, required this.artist, required this.tracks});

  /// The server's album id, or a made-up key for tracks without an album.
  final String key;
  final String name;
  final String artist;

  /// In disc and track order.
  final List<JellyfinItem> tracks;

  /// Tracks of an artist that have no album.
  bool get loose => key.startsWith('none:');

  /// The server's album id, when the tracks have one.
  String? get albumId => loose || key.startsWith('name:') ? null : key;

  /// A track whose picture is the album's cover.
  JellyfinItem get cover =>
      tracks.firstWhere((t) => t.albumImageOwner != null || t.hasPrimaryImage, orElse: () => tracks.first);

  int? get year => tracks.map((t) => t.year).whereType<int>().fold<int?>(null, (a, b) => a == null || b > a ? b : a);

  DateTime? get added => tracks
      .map((t) => t.dateCreated)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

  Duration get length => tracks.fold(Duration.zero, (sum, t) => sum + (t.runTime ?? Duration.zero));
}

class ArtistGroup {
  ArtistGroup({required this.name, required this.albums});

  final String name;

  /// By year, then name.
  final List<AlbumGroup> albums;

  List<JellyfinItem> get tracks => [for (final a in albums) ...a.tracks];

  int get trackCount => albums.fold(0, (n, a) => n + a.tracks.length);

  /// A track whose picture stands for the artist.
  JellyfinItem get cover => albums.first.cover;
}

/// Tracks into albums. Tracks with no album make one group per artist, "Other tracks".
List<AlbumGroup> groupByAlbum(List<JellyfinItem> tracks) {
  final groups = <String, List<JellyfinItem>>{};
  for (final t in tracks) {
    final key = t.albumId ?? (t.album != null ? 'name:${t.album}|${artistOf(t)}' : 'none:${artistOf(t)}');
    (groups[key] ??= []).add(t);
  }
  return [
    for (final MapEntry(:key, value: list) in groups.entries)
      AlbumGroup(
        key: key,
        name: key.startsWith('none:') ? 'Other tracks' : (list.first.album ?? 'Unknown album'),
        artist: _albumArtist(list),
        tracks: list..sort(albumOrder),
      ),
  ]..sort((a, b) => _byName(a.name, b.name));
}

/// The album's artist; "Various artists" for a compilation without one.
String _albumArtist(List<JellyfinItem> tracks) {
  final named = tracks.map((t) => t.albumArtist).whereType<String>().firstOrNull;
  if (named != null) return named;
  final all = tracks.map(artistOf).toSet();
  return all.length == 1 ? all.first : 'Various artists';
}

/// Tracks into artists, each with their albums.
List<ArtistGroup> groupByArtist(List<JellyfinItem> tracks) {
  final byArtist = <String, List<JellyfinItem>>{};
  for (final t in tracks) {
    (byArtist[artistOf(t)] ??= []).add(t);
  }
  return [
    for (final MapEntry(key: name, value: list) in byArtist.entries)
      ArtistGroup(
        name: name,
        albums: groupByAlbum(list)
          ..sort((a, b) {
            // Loose tracks last; albums by year, then name.
            final loose = (a.loose ? 1 : 0).compareTo(b.loose ? 1 : 0);
            if (loose != 0) return loose;
            final year = (a.year ?? 9999).compareTo(b.year ?? 9999);
            return year != 0 ? year : _byName(a.name, b.name);
          }),
      ),
  ]..sort((a, b) => _byName(a.name, b.name));
}

enum TrackSort {
  title('Title'),
  artist('Artist'),
  album('Album'),
  added('Recently added'),
  length('Length');

  const TrackSort(this.label);
  final String label;
}

enum AlbumSort {
  name('Name'),
  artist('Artist'),
  year('Year'),
  added('Recently added');

  const AlbumSort(this.label);
  final String label;
}

enum ArtistSort {
  name('Name'),
  tracks('Most tracks');

  const ArtistSort(this.label);
  final String label;
}

List<JellyfinItem> sortTracks(List<JellyfinItem> tracks, TrackSort by) {
  int compare(JellyfinItem a, JellyfinItem b) => switch (by) {
    TrackSort.title => _byName(a.name, b.name),
    TrackSort.artist => _then(
      _byName(artistOf(a), artistOf(b)),
      () => _then(_byName(a.album ?? '', b.album ?? ''), () => albumOrder(a, b)),
    ),
    TrackSort.album => _then(_byName(a.album ?? '\u{10FFFF}', b.album ?? '\u{10FFFF}'), () => albumOrder(a, b)),
    TrackSort.added => _then(_newer(a.dateCreated, b.dateCreated), () => _byName(a.name, b.name)),
    TrackSort.length => _then(
      (b.runTime ?? Duration.zero).compareTo(a.runTime ?? Duration.zero),
      () => _byName(a.name, b.name),
    ),
  };
  return [...tracks]..sort(compare);
}

List<AlbumGroup> sortAlbums(List<AlbumGroup> albums, AlbumSort by) {
  int compare(AlbumGroup a, AlbumGroup b) => switch (by) {
    AlbumSort.name => _byName(a.name, b.name),
    AlbumSort.artist => _then(_byName(a.artist, b.artist), () => _byName(a.name, b.name)),
    AlbumSort.year => _then((b.year ?? -1).compareTo(a.year ?? -1), () => _byName(a.name, b.name)),
    AlbumSort.added => _then(_newer(a.added, b.added), () => _byName(a.name, b.name)),
  };
  return [...albums]..sort(compare);
}

List<ArtistGroup> sortArtists(List<ArtistGroup> artists, ArtistSort by) => [...artists]
  ..sort(
    (a, b) => switch (by) {
      ArtistSort.name => _byName(a.name, b.name),
      ArtistSort.tracks => _then(b.trackCount.compareTo(a.trackCount), () => _byName(a.name, b.name)),
    },
  );

/// Whether a track has all of [query]'s words in its name, artists or album.
bool trackMatches(JellyfinItem t, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final hay = [t.name, ...t.artists, t.albumArtist ?? '', t.album ?? ''].join(' ').toLowerCase();
  return words.every(hay.contains);
}

int _then(int first, int Function() next) => first != 0 ? first : next();

/// Newer first; unknown dates last.
int _newer(DateTime? a, DateTime? b) => a == null
    ? (b == null ? 0 : 1)
    : b == null
    ? -1
    : b.compareTo(a);
