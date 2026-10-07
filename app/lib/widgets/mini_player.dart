import 'package:flutter/material.dart';

import '../services/playback.dart';
import 'artwork.dart';
import 'vinyl_art.dart';

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
        // A floating card over the page, with the track's progress along its bottom edge.
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Material(
              color: scheme.surfaceContainerHigh,
              elevation: 6,
              shadowColor: Colors.black54,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpen,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox.square(
                          dimension: 46,
                          child: artworkImage(item, fallback: const NoteTile()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          if (item.subtitle != null)
                            Text(item.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.primary)),
                        ]),
                      ),
                      StreamBuilder<bool>(
                        stream: pb.player.stream.playing,
                        initialData: pb.player.state.playing,
                        builder: (context, s) => IconButton.filled(
                          icon: Icon(s.data! ? Icons.pause : Icons.play_arrow, semanticLabel: s.data! ? 'Pause' : 'Play'),
                          onPressed: s.data! ? pb.pause : pb.play,
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close, semanticLabel: 'Stop'), onPressed: pb.stop),
                    ]),
                  ),
                  _Progress(pb: pb),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// How far the track has played, as a thin line; only this line follows the position.
class _Progress extends StatelessWidget {
  const _Progress({required this.pb});
  final Playback pb;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
        stream: pb.player.stream.position,
        initialData: pb.player.state.position,
        builder: (context, pos) {
          final total = pb.player.state.duration.inMilliseconds;
          final value = total > 0 ? (pos.data!.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
          return LinearProgressIndicator(value: value, minHeight: 3, backgroundColor: Colors.transparent);
        },
      );
}
