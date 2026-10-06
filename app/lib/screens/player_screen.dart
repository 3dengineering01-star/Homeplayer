import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api/common.dart';
import '../services/playback.dart';
import '../widgets/artwork.dart';
import '../widgets/track_sheet.dart';

/// Full-screen view of [Playback]. Leaving it stops a video; music keeps playing.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final Playback _pb = Playback.instance;

  @override
  void initState() {
    super.initState();
    _pb.screenOpened();
  }

  @override
  void dispose() {
    _pb.screenClosed();
    if (_pb.currentItem?.isVideo ?? false) unawaited(_pb.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The queue too: a stop on the first track leaves the index at 0 but empties it.
    return ListenableBuilder(
      listenable: Listenable.merge([_pb.items, _pb.current]),
      builder: (context, _) {
        final index = _pb.current.value;
        final item = _pb.currentItem;
        if (item == null) {
          // Stopped from the notification while this screen was open: go back to the list.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Nothing is playing')));
        }
        if (item.isVideo) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: 'Quality, audio and subtitles',
                  icon: const Icon(Icons.subtitles_outlined),
                  onPressed: () => showTrackSheet(context, _pb),
                ),
              ],
            ),
            // Subtitles are drawn by libass into the video, not by Flutter on top of it.
            body: Video(controller: _pb.video, subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false)),
          );
        }
        final count = _pb.items.value.length;
        return Scaffold(
          appBar: AppBar(title: Text('${index + 1} / $count')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: artworkImage(item, fallback: _noArt(context)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(item.title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center, maxLines: 2),
                if (item.subtitle != null) Text(item.subtitle!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                _SeekBar(pb: _pb),
                _Transport(pb: _pb, hasPrev: index > 0, hasNext: index < count - 1),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _noArt(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.music_note, size: 96),
      );
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.pb});
  final Playback pb;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final p = widget.pb.player;
    return StreamBuilder<Duration>(
      stream: p.stream.duration,
      initialData: p.state.duration,
      builder: (context, dur) => StreamBuilder<Duration>(
        stream: p.stream.position,
        initialData: p.state.position,
        builder: (context, pos) {
          final total = dur.data!.inMilliseconds.toDouble();
          final current = (_dragging ?? pos.data!.inMilliseconds.toDouble()).clamp(0.0, total > 0 ? total : 0.0);
          return Column(children: [
            Slider(
              value: current,
              max: total > 0 ? total : 1,
              onChanged: total > 0 ? (v) => setState(() => _dragging = v) : null,
              onChangeEnd: (v) {
                widget.pb.seek(Duration(milliseconds: v.round()));
                setState(() => _dragging = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(formatDuration(Duration(milliseconds: current.round()))),
                Text(formatDuration(dur.data!)),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.pb, required this.hasPrev, required this.hasNext});
  final Playback pb;
  final bool hasPrev;
  final bool hasNext;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(iconSize: 40, onPressed: hasPrev ? pb.skipToPrevious : null, icon: const Icon(Icons.skip_previous)),
      StreamBuilder<bool>(
        stream: pb.player.stream.playing,
        initialData: pb.player.state.playing,
        builder: (context, s) => IconButton.filled(
          iconSize: 56,
          onPressed: s.data! ? pb.pause : pb.play,
          icon: Icon(s.data! ? Icons.pause : Icons.play_arrow),
        ),
      ),
      IconButton(iconSize: 40, onPressed: hasNext ? pb.skipToNext : null, icon: const Icon(Icons.skip_next)),
    ]);
  }
}
