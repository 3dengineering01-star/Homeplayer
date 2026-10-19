import 'package:flutter/material.dart';

import '../api/dlna.dart';
import '../services/appearance.dart';
import '../services/playback.dart';
import '../services/tv_cast.dart';
import 'artwork.dart';
import 'glass.dart';
import 'vinyl_art.dart';

/// What a swipe on the mini player does.
enum MiniSwipe { none, next, previous, open }

/// A finger moved by [dx], [dy] and let go at [vx], [vy] (logical pixels, per second): sideways
/// changes the track (to the left: the next one, as the cards of a deck), up opens the player.
MiniSwipe miniSwipe(double dx, double dy, double vx, double vy) {
  if (dx.abs() > dy.abs()) {
    if (dx.abs() < 64 && vx.abs() < 600) return MiniSwipe.none;
    return (dx.abs() >= 24 ? dx : vx) < 0 ? MiniSwipe.next : MiniSwipe.previous;
  }
  return dy < -40 || (vy < -500 && dy < 0) ? MiniSwipe.open : MiniSwipe.none;
}

/// Bar at the bottom of every screen while music plays and the full player is closed. Swipe it
/// sideways for the next or previous track, up for the player.
/// It sits outside the navigator, where there is no Overlay, so no tooltips here.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pb = Playback.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([pb.items, pb.current, pb.screenOpen, pb.restored]),
      builder: (context, _) {
        final item = pb.currentItem;
        if (item == null || item.isVideo || pb.screenOpen.value) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        // A floating card over the page, with the track's progress along its bottom edge.
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: _Swipe(
              onSwipe: (s) => switch (s) {
                MiniSwipe.next => pb.skipToNext(),
                MiniSwipe.previous => pb.skipToPrevious(),
                MiniSwipe.open => onOpen(),
                MiniSwipe.none => null,
              },
              child: _Frame(
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
                      // The queue from the last run is not in the player yet (see Playback.restoreQueue).
                      if (pb.restored.value)
                        IconButton.filled(
                          icon: const Icon(Icons.play_arrow, semanticLabel: 'Play'),
                          onPressed: pb.play,
                        )
                      else
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
                  if (!pb.restored.value) _Progress(pb: pb),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bar at the bottom of every screen while something plays on a TV and its remote is closed:
/// tap for the remote. Outside the navigator too, so no tooltips.
class TvBar extends StatelessWidget {
  const TvBar({super.key, required this.onOpen});

  final void Function(TvCast cast) onOpen;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TvCast?>(
        valueListenable: TvCast.active,
        builder: (context, cast, _) => ValueListenableBuilder<bool>(
          valueListenable: TvCast.remoteShown,
          builder: (context, shown, _) {
            if (cast == null || shown) return const SizedBox.shrink();
            return ListenableBuilder(
              listenable: cast,
              builder: (context, _) {
                final theme = Theme.of(context);
                final total = cast.duration?.inMilliseconds ?? 0;
                final playing = cast.state == TvState.playing;
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: _Frame(
                      onTap: () => onOpen(cast),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 4, 6),
                          child: Row(children: [
                            Icon(Icons.cast_connected, color: theme.colorScheme.primary),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(cast.item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                Text(cast.error != null ? 'The TV does not answer' : 'On ${cast.tvName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: cast.error != null ? theme.colorScheme.error : theme.colorScheme.primary)),
                              ]),
                            ),
                            IconButton.filled(
                              icon: Icon(playing ? Icons.pause : Icons.play_arrow, semanticLabel: playing ? 'Pause' : 'Play'),
                              onPressed: cast.error == null ? cast.togglePause : null,
                            ),
                            IconButton(icon: const Icon(Icons.stop, semanticLabel: 'Stop on TV'), onPressed: cast.stop),
                          ]),
                        ),
                        LinearProgressIndicator(
                          value: total > 0 ? (cast.position.inMilliseconds / total).clamp(0.0, 1.0) : 0.0,
                          minHeight: 3,
                          backgroundColor: Colors.transparent,
                        ),
                      ]),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}

/// Follows the finger a little while it slides, then tells [onSwipe] what the swipe meant.
class _Swipe extends StatefulWidget {
  const _Swipe({required this.onSwipe, required this.child});

  final ValueChanged<MiniSwipe> onSwipe;
  final Widget child;

  @override
  State<_Swipe> createState() => _SwipeState();
}

class _SwipeState extends State<_Swipe> {
  Offset _moved = Offset.zero;

  void _end(Velocity v) {
    final s = miniSwipe(_moved.dx, _moved.dy, v.pixelsPerSecond.dx, v.pixelsPerSecond.dy);
    setState(() => _moved = Offset.zero);
    widget.onSwipe(s);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onPanUpdate: (d) => setState(() => _moved += d.delta),
        onPanEnd: (d) => _end(d.velocity),
        onPanCancel: () => setState(() => _moved = Offset.zero),
        child: AnimatedContainer(
          duration: Duration(milliseconds: _moved == Offset.zero ? 200 : 0),
          curve: Curves.easeOut,
          // Sideways it follows a third of the way; up only a little, the player opens instead.
          transform: _moved.dx.abs() > _moved.dy.abs()
              ? Matrix4.translationValues(_moved.dx / 3, 0, 0)
              : Matrix4.translationValues(0, _moved.dy < 0 ? _moved.dy / 6 : 0, 0),
          child: widget.child,
        ),
      );
}

/// The bar's card: a pane of glass with the glass style, else a raised card.
class _Frame extends StatelessWidget {
  const _Frame({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (GlassLook.from(context).on) return GlassPane(radius: 22, onTap: onTap, child: child);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
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
