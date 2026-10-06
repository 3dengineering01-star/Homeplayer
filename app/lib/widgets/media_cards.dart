import 'package:flutter/material.dart';

import '../api/jellyfin.dart';

/// A picture from the server that fades in, with an icon while loading or without a picture.
class NetImage extends StatelessWidget {
  const NetImage({super.key, required this.url, required this.headers, required this.icon, this.fit = BoxFit.cover});

  final Uri? url;
  final Map<String, String> headers;
  final IconData icon;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(icon, color: scheme.onSurfaceVariant, size: 32)),
    );
    if (url == null) return placeholder;
    return Image.network(
      url.toString(),
      headers: headers,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : Stack(fit: StackFit.expand, children: [
              placeholder,
              AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 250), child: child),
            ]),
    );
  }
}

IconData itemTypeIcon(JellyfinItem item) => switch (item.type) {
      'Series' || 'Season' || 'Episode' => Icons.tv,
      'MusicAlbum' || 'Audio' => Icons.album,
      'MusicArtist' => Icons.person,
      'CollectionFolder' || 'UserView' => Icons.video_library_outlined,
      _ => item.isFolder ? Icons.folder : Icons.movie,
    };

/// Watched mark, or the number of episodes left, in the corner of a picture.
class _Badge extends StatelessWidget {
  const _Badge({required this.item});
  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = item.unwatched;
    if (item.played) {
      return CircleAvatar(
        radius: 12,
        backgroundColor: scheme.primary,
        child: Icon(Icons.check, size: 16, color: scheme.onPrimary, semanticLabel: 'Watched'),
      );
    }
    if (left != null && left > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
        child: Text('$left', style: TextStyle(color: scheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
      );
    }
    return const SizedBox.shrink();
  }
}

/// A thin progress bar along the bottom of a picture.
class _Progress extends StatelessWidget {
  const _Progress({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: LinearProgressIndicator(value: value, minHeight: 4, backgroundColor: Colors.black38),
      );
}

/// A poster (2:3 for movies and series, square for albums) with the name and year under it.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.client,
    required this.onTap,
    this.onLongPress,
    this.width = 120,
    this.square = false,
  });

  final JellyfinItem item;
  final JellyfinClient client;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double width;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = item.played ? null : item.progress;
    final sub = item.type == 'MusicAlbum' ? item.subtitle : item.year?.toString();
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: square ? 1 : 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                Hero(
                  tag: 'poster-${item.id}',
                  child: NetImage(
                    url: client.imageUrl(item, height: (width * (square ? 1 : 1.5) * 2).round()),
                    headers: client.headers,
                    icon: itemTypeIcon(item),
                  ),
                ),
                Positioned(top: 6, right: 6, child: _Badge(item: item)),
                if (progress != null) _Progress(value: progress),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
            child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
          ),
          if (sub != null && sub.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ]),
      ),
    );
  }
}

/// A 16:9 card: an episode's still or a movie's backdrop, with progress, name and episode.
class WideCard extends StatelessWidget {
  const WideCard({
    super.key,
    required this.item,
    required this.client,
    required this.onTap,
    this.onLongPress,
    this.width = 240,
    this.image,
    this.title,
    this.subtitle,
  });

  final JellyfinItem item;
  final JellyfinClient client;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double width;

  /// Overrides the picture (a library's own image) and the texts.
  final Uri? image;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = item.played ? null : item.progress;
    final isEpisode = item.type == 'Episode';
    final name = title ?? (isEpisode ? (item.seriesName ?? item.name) : item.name);
    final sub = subtitle ??
        (isEpisode
            ? [
                if (item.seasonNumber != null && item.indexNumber != null) 'S${item.seasonNumber}E${item.indexNumber}',
                item.name,
              ].join(' · ')
            : item.year?.toString());
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                NetImage(
                  url: image ?? client.wideUrl(item, width: (width * 2).round()) ?? client.imageUrl(item, height: 360),
                  headers: client.headers,
                  icon: itemTypeIcon(item),
                ),
                if (progress != null) _Progress(value: progress),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
          ),
          if (sub != null && sub.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ]),
      ),
    );
  }
}

/// A titled row of cards that scrolls sideways.
class Shelf extends StatelessWidget {
  const Shelf({super.key, required this.title, required this.height, required this.children, this.onMore});

  final String title;
  final double height;
  final List<Widget> children;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        child: Row(children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          if (onMore != null)
            TextButton(onPressed: onMore, child: const Text('All')),
        ]),
      ),
      SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => children[i],
        ),
      ),
    ]);
  }
}
