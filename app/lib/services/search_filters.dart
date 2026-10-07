/// What to look for on a Jellyfin server: words, a kind of item, years, genres, watched or not,
/// and the order. Turned into the server's query here, apart from the screen, so it is tested.
library;

/// The kinds of items the search can be narrowed to.
enum SearchKind {
  all('All', 'Movie,Series,Episode,Audio,MusicVideo,Video,Photo,Playlist,BoxSet'),
  movies('Movies', 'Movie'),
  shows('Shows', 'Series'),
  episodes('Episodes', 'Episode'),
  artists('Artists', null),
  albums('Albums', null),
  tracks('Tracks', 'Audio'),
  videos('Videos', 'Video,MusicVideo'),
  photos('Photos', 'Photo'),
  playlists('Playlists', 'Playlist');

  const SearchKind(this.label, this.types);
  final String label;

  /// Jellyfin item types for /Items; null for artists, which have a list of their own, and for
  /// albums, which the app makes from the tracks as the music screen does: the server may have
  /// no albums for music folders it links to.
  final String? types;
}

/// Watched or not, for movies and episodes.
enum Watched {
  any('Any'),
  unwatched('Not watched'),
  watched('Watched');

  const Watched(this.label);
  final String label;
}

/// The order of the results.
enum SearchSort {
  relevance('Best match', null, false),
  name('Name', 'SortName', false),
  newest('Newest', 'ProductionYear,PremiereDate,SortName', true),
  added('Recently added', 'DateCreated,SortName', true),
  rating('Rating', 'CommunityRating,SortName', true);

  const SearchSort(this.label, this.sortBy, this.descending);
  final String label;
  final String? sortBy;
  final bool descending;
}

class SearchFilters {
  const SearchFilters({
    this.text = '',
    this.kind = SearchKind.all,
    this.fromYear,
    this.toYear,
    this.genres = const {},
    this.watched = Watched.any,
    this.sort = SearchSort.relevance,
  });

  final String text;
  final SearchKind kind;
  final int? fromYear;
  final int? toYear;
  final Set<String> genres;
  final Watched watched;
  final SearchSort sort;

  /// Narrowing beyond the words and the kind, shown as a count on the filter button.
  int get extraFilters =>
      (fromYear != null || toYear != null ? 1 : 0) + (genres.isNotEmpty ? 1 : 0) + (watched != Watched.any ? 1 : 0);

  /// Worth asking the server: some words, or a narrowing that is not the whole server.
  bool get isReady => text.trim().isNotEmpty || extraFilters > 0 || kind != SearchKind.all;

  /// Tracks and albums are also found by their artist's name, which the server's own word
  /// search does not look at.
  bool get byArtist => text.trim().isNotEmpty && extraFilters == 0 && (kind == SearchKind.all || kind == SearchKind.tracks);

  /// Albums, found among the tracks: all of them on their own tab, by name or artist with All.
  bool get wantsAlbums =>
      kind == SearchKind.albums || (kind == SearchKind.all && text.trim().isNotEmpty && extraFilters == 0);

  /// Artists are looked for by name only: years, genres and watched marks belong to items.
  bool get wantsArtists =>
      (kind == SearchKind.artists || (kind == SearchKind.all && extraFilters == 0)) && text.trim().isNotEmpty;

  SearchFilters copyWith({
    String? text,
    SearchKind? kind,
    int? Function()? fromYear,
    int? Function()? toYear,
    Set<String>? genres,
    Watched? watched,
    SearchSort? sort,
  }) => SearchFilters(
    text: text ?? this.text,
    kind: kind ?? this.kind,
    fromYear: fromYear == null ? this.fromYear : fromYear(),
    toYear: toYear == null ? this.toYear : toYear(),
    genres: genres ?? this.genres,
    watched: watched ?? this.watched,
    sort: sort ?? this.sort,
  );

  /// Years from [fromYear] to [toYear] as Jellyfin takes them: each one listed. A missing end
  /// is open: from 1900, or up to [now]'s year.
  List<int> years({DateTime? now}) {
    if (fromYear == null && toYear == null) return const [];
    final last = toYear ?? (now ?? DateTime.now()).year;
    var first = fromYear ?? 1900;
    if (first > last) return const [];
    // Not a hundred years of query string for "before 2000".
    if (last - first > 150) first = last - 150;
    return [for (var y = first; y <= last; y++) y];
  }

  Map<String, String> itemsQuery(String userId, {int limit = 100, DateTime? now}) {
    final words = text.trim();
    final y = years(now: now);
    final sortBy = sort.sortBy ?? (words.isEmpty ? SearchSort.name.sortBy : null);
    return {
      'userId': userId,
      'recursive': 'true',
      'includeItemTypes': kind.types ?? SearchKind.all.types!,
      'limit': '$limit',
      'fields': 'PrimaryImageAspectRatio,MediaSourceCount,ProductionYear,ChildCount',
      'enableUserData': 'true',
      // Not excludeLocationTypes=Virtual: albums of loose files can be virtual, and the search
      // found no albums at all with it. Missing episodes are what should stay out.
      'isMissing': 'false',
      if (words.isNotEmpty) 'searchTerm': words,
      if (y.isNotEmpty) 'years': y.join(','),
      if (genres.isNotEmpty) 'genres': genres.join('|'),
      if (watched != Watched.any) 'isPlayed': '${watched == Watched.watched}',
      'sortBy': ?sortBy,
      if (sortBy != null) 'sortOrder': sort.descending ? 'Descending' : 'Ascending',
    };
  }

  /// Tracks and albums of the artists found by name.
  Map<String, String> byArtistQuery(String userId, List<String> artistIds, {int limit = 100}) => {
        'userId': userId,
        'recursive': 'true',
        'artistIds': artistIds.join(','),
        'includeItemTypes': 'Audio',
        'limit': '$limit',
        'sortBy': 'Album,ParentIndexNumber,IndexNumber,SortName',
        'fields': 'PrimaryImageAspectRatio,MediaSourceCount,ProductionYear,Path',
        'enableUserData': 'true',
      };

  Map<String, String> artistsQuery(String userId, {int limit = 50}) => {
    'userId': userId,
    'searchTerm': text.trim(),
    'limit': '$limit',
    'fields': 'PrimaryImageAspectRatio',
  };
}

/// The last searches, newest first: [text] moved to the front, at most [keep] of them.
List<String> rememberSearch(List<String> recent, String text, {int keep = 10}) {
  final t = text.trim();
  if (t.isEmpty) return recent;
  return [t, ...recent.where((r) => r.toLowerCase() != t.toLowerCase())].take(keep).toList();
}
