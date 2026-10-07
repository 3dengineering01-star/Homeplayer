import 'package:flutter/material.dart';

import '../api/jellyfin.dart';

/// How the home screen shows a library: its icon, the Jellyfin item types it counts
/// (null: nothing worth counting) and the words for one and many of them.
typedef LibraryKind = ({IconData icon, String? types, String one, String many});

LibraryKind libraryKind(String? collectionType) => switch (collectionType) {
      'movies' => (icon: Icons.movie_outlined, types: 'Movie', one: 'movie', many: 'movies'),
      'tvshows' => (icon: Icons.tv, types: 'Series', one: 'show', many: 'shows'),
      'music' => (icon: Icons.library_music_outlined, types: 'MusicAlbum', one: 'album', many: 'albums'),
      'musicvideos' => (icon: Icons.music_video_outlined, types: 'MusicVideo', one: 'clip', many: 'clips'),
      'boxsets' => (icon: Icons.collections_bookmark_outlined, types: 'BoxSet', one: 'collection', many: 'collections'),
      'homevideos' => (icon: Icons.perm_media_outlined, types: 'Video,Photo', one: 'file', many: 'files'),
      'photos' => (icon: Icons.photo_library_outlined, types: 'Photo', one: 'photo', many: 'photos'),
      'playlists' => (icon: Icons.queue_music, types: 'Playlist', one: 'playlist', many: 'playlists'),
      'books' => (icon: Icons.menu_book_outlined, types: 'Book', one: 'book', many: 'books'),
      _ => (icon: Icons.folder_outlined, types: null, one: 'item', many: 'items'),
    };

/// Music libraries without album tags hold bare tracks: counted as tracks instead of albums.
const LibraryKind tracksKind = (icon: Icons.library_music_outlined, types: 'Audio', one: 'track', many: 'tracks');

/// "1 movie", "124 movies".
String countLabel(int n, LibraryKind kind) => '$n ${n == 1 ? kind.one : kind.many}';

/// The hue of the [index]th library tile: the theme's own hue turned by a fifth of the colour
/// wheel per tile, so neighbouring tiles differ clearly while staying in the theme's mood.
Color tileSeed(Color primary, int index) {
  final hsl = HSLColor.fromColor(primary);
  return hsl.withHue((hsl.hue + 72 * (index % 5)) % 360).toColor();
}

/// A big button for one library: its icon, name and how much is in it, each library in its
/// own colour.
class LibraryTile extends StatelessWidget {
  const LibraryTile({super.key, required this.library, required this.index, required this.onTap, this.count});

  final JellyfinItem library;

  /// The tile's place on the screen, which picks its colour.
  final int index;
  final VoidCallback onTap;

  /// "124 movies", or null while counting or for libraries with nothing to count.
  final String? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final own = index == 0
        ? scheme
        : ColorScheme.fromSeed(seedColor: tileSeed(scheme.primary, index), brightness: theme.brightness);
    final (bg, fg) = (own.primaryContainer, own.onPrimaryContainer);
    final icon = libraryKind(library.collectionType).icon;
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Stack(children: [
          // A large faint copy of the icon in the corner, for a bit of picture.
          Positioned(
            right: -14,
            bottom: -18,
            child: Icon(icon, size: 96, color: fg.withValues(alpha: 0.10)),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: fg.withValues(alpha: 0.12),
                child: Icon(icon, color: fg, size: 22),
              ),
              const Spacer(),
              Text(library.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
              AnimatedOpacity(
                opacity: count == null ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: Text(count ?? ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.8))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
