import 'package:flutter/material.dart';

import '../services/playback.dart';
import 'artwork.dart';

/// Bar at the bottom of every screen while music plays and the full player is closed.
/// It sits outside the navigator, where there is no Overlay, so no tooltips here.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pb = Playback.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([pb.items, pb.current, pb.screenOpen]),
      builder: (context, _) {
        final item = pb.currentItem;
        if (item == null || item.isVideo || pb.screenOpen.value) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox.square(
                      dimension: 44,
                      child: artworkImage(item, fallback: Icon(Icons.music_note, color: scheme.onSurfaceVariant)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (item.subtitle != null)
                        Text(item.subtitle!,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                  StreamBuilder<bool>(
                    stream: pb.player.stream.playing,
                    initialData: pb.player.state.playing,
                    builder: (context, s) => IconButton(
                      icon: Icon(s.data! ? Icons.pause : Icons.play_arrow, semanticLabel: s.data! ? 'Pause' : 'Play'),
                      onPressed: s.data! ? pb.pause : pb.play,
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, semanticLabel: 'Stop'), onPressed: pb.stop),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
