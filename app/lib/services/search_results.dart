import '../api/jellyfin.dart';

/// Search results in sections by kind, in a fixed order: movies first, photos last.
List<(String, List<JellyfinItem>)> groupResults(List<JellyfinItem> items) {
  const sections = [
    ('Movies', {'Movie'}),
    ('Shows', {'Series'}),
    ('Episodes', {'Episode'}),
    ('Artists', {'MusicArtist'}),
    ('Albums', {'MusicAlbum'}),
    ('Tracks', {'Audio'}),
    ('Videos', {'Video', 'MusicVideo'}),
    ('Collections', {'BoxSet'}),
    ('Playlists', {'Playlist'}),
    ('Photos', {'Photo'}),
  ];
  final known = {for (final (_, types) in sections) ...types};
  return [
    for (final (title, types) in sections)
      if (items.where((i) => types.contains(i.type)).toList() case final list when list.isNotEmpty) (title, list),
    if (items.where((i) => !known.contains(i.type)).toList() case final rest when rest.isNotEmpty) ('Other', rest),
  ];
}

/// The line under a result: what it is and what it belongs to.
String resultSubtitle(JellyfinItem i) {
  final parts = switch (i.type) {
    'Movie' => [i.year?.toString()],
    'Series' => [i.year?.toString()],
    'Episode' => [i.subtitle],
    'MusicAlbum' => [i.albumArtist, i.year?.toString()],
    'Audio' => [i.subtitle, i.album],
    'MusicArtist' => const <String?>[],
    'Playlist' => [i.childCount == null ? null : '${i.childCount} ${i.childCount == 1 ? 'item' : 'items'}'],
    _ => [i.year?.toString()],
  };
  return parts.whereType<String>().where((p) => p.isNotEmpty).join(' · ');
}
