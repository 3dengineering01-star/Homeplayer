import 'package:flutter/material.dart';

import '../api/jellyfin.dart';
import '../widgets/async_list.dart';
import '../widgets/track_tile.dart';
import 'jellyfin_actions.dart';

/// Libraries at the top level, then any folder: series, season, album...
class JellyfinBrowser extends StatefulWidget {
  const JellyfinBrowser({super.key, required this.client, required this.title, this.parentId});

  final JellyfinClient client;
  final String title;
  final String? parentId;

  @override
  State<JellyfinBrowser> createState() => _JellyfinBrowserState();
}

class _JellyfinBrowserState extends State<JellyfinBrowser> with JellyfinActions {
  /// Bumped to reload the list, e.g. to show new progress after watching.
  int _generation = 0;

  @override
  JellyfinClient get client => widget.client;

  @override
  void refresh() => setState(() => _generation++);

  /// A square in the photo grid: the picture, a play mark on videos, a name on folders.
  Widget _tile(BuildContext context, List<JellyfinItem> items, JellyfinItem item) {
    final theme = Theme.of(context);
    final url = item.isPhoto ? client.photoUrl(item, maxSide: 300) : client.imageUrl(item, height: 300);
    final fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(itemIcon(item), size: 32),
    );
    // The name for screen readers (and test tools): a photo tile has no text of its own.
    return Semantics(
      label: item.isFolder ? null : item.name,
      button: true,
      child: InkWell(
      onTap: () => openItem(items, item),
      onLongPress: item.isPlayable || item.isFolder ? () => itemActions(items, item) : null,
      child: Stack(fit: StackFit.expand, children: [
        url == null
            ? fallback
            : Image.network(url.toString(),
                headers: client.headers, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
        if (item.isVideo)
          const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 36)),
        if (item.isFolder)
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(4),
              child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
      ]),
      ),
    );
  }

  Widget? _subtitle(JellyfinItem item) {
    final text = item.subtitle;
    final progress = item.played ? null : item.progress;
    if ((text == null || text.isEmpty) && progress == null) return null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (text != null && text.isNotEmpty) Text(text),
      if (progress != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: LinearProgressIndicator(value: progress, minHeight: 3, borderRadius: BorderRadius.circular(2)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.parentId;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: AsyncList<JellyfinItem>(
        key: ValueKey(_generation),
        load: () => id == null ? client.views() : client.children(id),
        // Phone photo folders read better as a grid of thumbnails.
        useGrid: (items) => items.any((i) => i.isPhoto),
        gridItemBuilder: (context, items, i) => _tile(context, items, items[i]),
        itemBuilder: (context, items, i) {
          final item = items[i];
          if (item.type == 'Audio') {
            return TrackTile(
              client: client,
              item: item,
              onTap: () => openItem(items, item),
              onLongPress: () => itemActions(items, item),
            );
          }
          return ListTile(
            leading: ArtThumb(
              url: client.imageUrl(item, height: 168),
              headers: client.headers,
              icon: itemIcon(item),
              aspect: item.imageAspect,
            ),
            title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: _subtitle(item),
            trailing: !item.isPlayable
                ? null
                : item.played
                    ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, semanticLabel: 'Watched')
                    : const Icon(Icons.play_arrow),
            onTap: () => openItem(items, item),
            onLongPress: item.isPlayable || item.isFolder ? () => itemActions(items, item) : null,
          );
        },
      ),
    );
  }
}
