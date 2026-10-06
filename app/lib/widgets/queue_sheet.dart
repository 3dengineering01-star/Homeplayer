import 'package:flutter/material.dart';

import '../api/common.dart';
import '../services/playback.dart';
import 'artwork.dart';

/// "Play next" or "Add to queue" for [tracks] named [title].
Future<void> showQueueMenu(BuildContext context, String title, List<PlayItem> tracks) async {
  final messenger = ScaffoldMessenger.of(context);
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ListTile(
          leading: const Icon(Icons.playlist_play),
          title: const Text('Play next'),
          onTap: () => Navigator.pop(context, 'next'),
        ),
        ListTile(
          leading: const Icon(Icons.playlist_add),
          title: const Text('Add to queue'),
          onTap: () => Navigator.pop(context, 'queue'),
        ),
      ]),
    ),
  );
  if (action == null) return;
  final pb = Playback.instance;
  final wasPlaying = pb.currentItem != null && !pb.currentItem!.isVideo;
  action == 'next' ? await pb.playNext(tracks) : await pb.addToQueue(tracks);
  messenger.showSnackBar(SnackBar(
      content: Text(!wasPlaying
          ? 'Playing'
          : action == 'next'
              ? 'Plays next'
              : 'Added to the queue')));
}

/// The queue: tap to play, drag the handle to reorder, swipe to remove.
void showQueueSheet(BuildContext context, Playback pb) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => _QueueList(pb: pb, scroll: scroll),
    ),
  );
}

class _QueueList extends StatefulWidget {
  const _QueueList({required this.pb, required this.scroll});
  final Playback pb;
  final ScrollController scroll;

  @override
  State<_QueueList> createState() => _QueueListState();
}

class _QueueListState extends State<_QueueList> {
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final pb = widget.pb;
    return ListenableBuilder(
      listenable: Listenable.merge([pb.items, pb.current, pb.shuffle]),
      builder: (context, _) {
        final list = pb.items.value;
        final playing = pb.current.value;
        final theme = Theme.of(context);
        // Open at the playing track rather than at the top of a long queue.
        if (!_scrolled && playing > 2) {
          _scrolled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (widget.scroll.hasClients) widget.scroll.jumpTo((playing - 1) * 64.0);
          });
        }
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(children: [
              Expanded(
                child: Text('Queue · ${list.length} ${list.length == 1 ? 'track' : 'tracks'}',
                    style: theme.textTheme.titleMedium),
              ),
              FilterChip(
                avatar: const Icon(Icons.shuffle, size: 18),
                label: const Text('Shuffle'),
                selected: pb.shuffle.value,
                onSelected: pb.setShuffle,
              ),
            ]),
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollController: widget.scroll,
              buildDefaultDragHandles: false,
              itemCount: list.length,
              onReorderItem: pb.moveQueueItem,
              itemBuilder: (context, i) {
                final item = list[i];
                final now = i == playing;
                final tile = ListTile(
                  minTileHeight: 64,
                  selected: now,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox.square(
                      dimension: 44,
                      child: now
                          ? ColoredBox(
                              color: theme.colorScheme.primaryContainer,
                              child: Icon(Icons.graphic_eq, color: theme.colorScheme.onPrimaryContainer),
                            )
                          : artworkImage(item, fallback: const Icon(Icons.music_note)),
                    ),
                  ),
                  title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: item.subtitle == null ? null : Text(item.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
                  ),
                  onTap: now ? null : () => pb.skipToQueueItem(i),
                );
                return Dismissible(
                  key: ObjectKey(item),
                  // The playing track stays: remove it by skipping.
                  direction: now ? DismissDirection.none : DismissDirection.horizontal,
                  background: Container(
                    color: theme.colorScheme.errorContainer,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
                  ),
                  secondaryBackground: Container(
                    color: theme.colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
                  ),
                  onDismissed: (_) => pb.removeFromQueue(i),
                  child: tile,
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}
