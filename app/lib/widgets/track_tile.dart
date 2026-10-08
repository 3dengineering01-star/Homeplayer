import 'package:flutter/material.dart';

import '../api/jellyfin.dart';
import '../services/playback.dart';
import '../services/search_index.dart';
import 'highlighted_text.dart';
import 'media_cards.dart';
import 'vinyl_art.dart';

/// A track: its cover (or the theme's note), name and artist, length; the one playing is marked.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.client,
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.query = '',
  });

  final JellyfinClient client;
  final JellyfinItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Words being searched for, marked in the name and the line under it.
  final String query;

  @override
  Widget build(BuildContext context) {
    final pb = Playback.maybe;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: pb == null ? const _Never() : Listenable.merge([pb.items, pb.current]),
      builder: (context, _) {
        // The stream URL carries the item's id.
        final now = pb?.currentItem?.url.path.contains(item.id) ?? false;
        final url = client.imageUrl(item, height: 112);
        return ListTile(
          selected: now,
          onTap: onTap,
          onLongPress: onLongPress,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.square(
              dimension: 48,
              child: url == null ? const NoteTile() : NetImage(url: url, headers: client.headers, icon: Icons.music_note),
            ),
          ),
          title: HighlightedText(item.name,
              query: query, style: now ? const TextStyle(fontWeight: FontWeight.w700) : null),
          subtitle: switch (foundByFileName(item, query) ? 'File: ${item.fileName}' : item.subtitle) {
            null => null,
            final sub => HighlightedText(sub, query: query),
          },
          trailing: now
              ? StreamBuilder<bool>(
                  stream: pb!.player.stream.playing,
                  initialData: pb.player.state.playing,
                  builder: (context, s) => Icon(s.data! ? Icons.graphic_eq : Icons.pause,
                      color: scheme.primary, semanticLabel: s.data! ? 'Playing' : 'Paused'),
                )
              : item.runTime == null
                  ? null
                  : Text(_clock(item.runTime!), style: Theme.of(context).textTheme.bodySmall),
        );
      },
    );
  }

  static String _clock(Duration d) => '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

/// Nothing to listen to: no player yet.
class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
