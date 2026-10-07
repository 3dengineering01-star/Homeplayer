import 'dart:math';

import 'package:flutter/material.dart';

import '../api/jellyfin.dart';
import '../services/appearance.dart';

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

/// The [index]th library's colours: a background and what goes on it.
(Color, Color) libraryColors(BuildContext context, int index) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final own = index == 0
      ? scheme
      : ColorScheme.fromSeed(seedColor: tileSeed(scheme.primary, index), brightness: theme.brightness);
  return (own.primaryContainer, own.onPrimaryContainer);
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
    final (bg, fg) = libraryColors(context, index);
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

/// One library as a line: a round icon in its colour, the name, how much is in it.
class LibraryRow extends StatelessWidget {
  const LibraryRow({super.key, required this.library, required this.index, required this.onTap, this.count});

  final JellyfinItem library;
  final int index;
  final VoidCallback onTap;
  final String? count;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = libraryColors(context, index);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: bg,
        child: Icon(libraryKind(library.collectionType).icon, color: fg),
      ),
      title: Text(library.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: count == null ? null : Text(count!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// One library as a round icon with its name under it, like an app on the phone's home screen.
class LibraryCircle extends StatelessWidget {
  const LibraryCircle({super.key, required this.library, required this.index, required this.onTap, this.count});

  final JellyfinItem library;
  final int index;
  final VoidCallback onTap;
  final String? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = libraryColors(context, index);
    return Semantics(
      button: true,
      label: [library.name, ?count].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          // A gap between neighbours' names, which with big letters ran together.
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [bg, Color.lerp(bg, fg, 0.18)!],
                ),
              ),
              child: Icon(libraryKind(library.collectionType).icon, color: fg, size: 30),
            ),
            const SizedBox(height: 6),
            Text(library.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge),
            Text(count ?? ' ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// The server's libraries the way [layout] says: big tiles two to a row, a list, or round icons.
class LibrariesView extends StatelessWidget {
  const LibrariesView({
    super.key,
    required this.layout,
    required this.libraries,
    required this.counts,
    required this.onOpen,
  });

  final LibraryLayout layout;
  final List<JellyfinItem> libraries;

  /// "124 movies" by library id.
  final Map<String, String> counts;
  final void Function(JellyfinItem library) onOpen;

  @override
  Widget build(BuildContext context) {
    final entries = libraries.indexed.toList();
    final width = MediaQuery.sizeOf(context).width;
    // Heights grow with the phone's text size, so bigger letters still fit.
    final text = MediaQuery.textScalerOf(context);
    return switch (layout) {
      LibraryLayout.tiles => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // Icon and padding, then the name and the count.
              mainAxisExtent: max((width - 44) / 2 / 1.6, 80 + text.scale(44)),
            ),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (i, l) in entries)
                LibraryTile(library: l, index: i, count: counts[l.id], onTap: () => onOpen(l)),
            ],
          ),
        ),
      LibraryLayout.list => Column(children: [
          for (final (i, l) in entries)
            LibraryRow(library: l, index: i, count: counts[l.id], onTap: () => onOpen(l)),
        ]),
      LibraryLayout.circles => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              // Four across on a phone held upright, more where there is room.
              crossAxisCount: (width / 96).floor().clamp(3, 8),
              // The circle and padding, then the name and the count.
              mainAxisExtent: 88 + text.scale(40),
            ),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (i, l) in entries)
                LibraryCircle(library: l, index: i, count: counts[l.id], onTap: () => onOpen(l)),
            ],
          ),
        ),
    };
  }
}

/// The button by the "Libraries" heading that picks tiles, a list or round icons.
class LibraryLayoutButton extends StatelessWidget {
  const LibraryLayoutButton({super.key, required this.look});

  final Appearance look;

  @override
  Widget build(BuildContext context) => PopupMenuButton<LibraryLayout>(
        tooltip: 'View',
        icon: Icon(look.libraries.icon),
        initialValue: look.libraries,
        onSelected: (l) => AppearanceStore.set(look.copyWith(libraries: l)),
        itemBuilder: (_) => [
          for (final l in LibraryLayout.values)
            PopupMenuItem(
              value: l,
              child: ListTile(leading: Icon(l.icon), title: Text(l.label), selected: l == look.libraries),
            ),
        ],
      );
}
