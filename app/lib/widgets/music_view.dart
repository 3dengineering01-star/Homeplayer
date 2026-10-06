import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../api/common.dart';
import '../screens/equalizer_screen.dart';
import '../services/playback.dart';
import '../services/video_tuning.dart';
import 'artwork.dart';
import 'queue_sheet.dart';

/// The music player: big cover over its own blurred colours, the controls under it.
/// Swipe the cover sideways for the next or previous track, double-tap it to pause, swipe the
/// screen down to close.
class MusicView extends StatelessWidget {
  const MusicView({super.key, required this.pb, required this.item, required this.index, required this.count});

  final Playback pb;
  final PlayItem item;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final noArt = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: 96, color: scheme.onSurfaceVariant),
    );
    return Scaffold(
      body: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 400) Navigator.of(context).maybePop();
        },
        child: Stack(fit: StackFit.expand, children: [
          // The cover's colours, blurred, behind everything.
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.decal),
            child: artworkImage(item, fallback: ColoredBox(color: scheme.surface)),
          ),
          ColoredBox(color: scheme.surface.withValues(alpha: 0.72)),
          SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              final cover = _Cover(pb: pb, item: item, fallback: noArt);
              final controls = _Controls(pb: pb, item: item, hasPrev: index > 0 || pb.repeat.value == Repeat.all, hasNext: index < count - 1 || pb.repeat.value == Repeat.all);
              final top = _TopBar(pb: pb, index: index, count: count);
              if (box.maxWidth > box.maxHeight) {
                return Column(children: [
                  top,
                  Expanded(
                    child: Row(children: [
                      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(24, 0, 12, 16), child: cover)),
                      Expanded(child: Center(child: SingleChildScrollView(child: controls))),
                    ]),
                  ),
                ]);
              }
              return Column(children: [
                top,
                Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(32, 8, 32, 16), child: cover)),
                controls,
                const SizedBox(height: 8),
              ]);
            }),
          ),
        ]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.pb, required this.index, required this.count});
  final Playback pb;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton(
          tooltip: 'Close',
          iconSize: 32,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
        Expanded(
          child: Column(children: [
            Text('Now playing', style: Theme.of(context).textTheme.labelMedium),
            Text('${index + 1} of $count', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        IconButton(
          tooltip: 'Queue',
          onPressed: () => showQueueSheet(context, pb),
          icon: const Icon(Icons.queue_music),
        ),
      ]);
}

class _Cover extends StatelessWidget {
  const _Cover({required this.pb, required this.item, required this.fallback});
  final Playback pb;
  final PlayItem item;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => GestureDetector(
        // The whole area around the cover takes the swipe, not only the picture.
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => pb.player.state.playing ? pb.pause() : pb.play(),
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -300) pb.skipToNext();
          if (v > 300) pb.skipToPrevious();
        },
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Material(
                key: ObjectKey(item),
                elevation: 12,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: artworkImage(item, fallback: fallback),
              ),
            ),
          ),
        ),
      );
}

class _Controls extends StatelessWidget {
  const _Controls({required this.pb, required this.item, required this.hasPrev, required this.hasNext});
  final Playback pb;
  final PlayItem item;
  final bool hasPrev;
  final bool hasNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(children: [
            Text(item.title,
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (item.subtitle != null)
              Text(item.subtitle!,
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(height: 8),
        MusicSeekBar(pb: pb),
        ListenableBuilder(
          listenable: Listenable.merge([pb.shuffle, pb.repeat]),
          builder: (context, _) => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton(
              tooltip: pb.shuffle.value ? 'Shuffle on' : 'Shuffle off',
              color: pb.shuffle.value ? on : null,
              onPressed: () => pb.setShuffle(!pb.shuffle.value),
              icon: const Icon(Icons.shuffle),
            ),
            IconButton(
              tooltip: 'Previous',
              iconSize: 40,
              onPressed: hasPrev ? pb.skipToPrevious : null,
              icon: const Icon(Icons.skip_previous),
            ),
            StreamBuilder<bool>(
              stream: pb.player.stream.playing,
              initialData: pb.player.state.playing,
              builder: (context, s) => IconButton.filled(
                tooltip: s.data! ? 'Pause' : 'Play',
                iconSize: 56,
                onPressed: s.data! ? pb.pause : pb.play,
                icon: Icon(s.data! ? Icons.pause : Icons.play_arrow),
              ),
            ),
            IconButton(
              tooltip: 'Next',
              iconSize: 40,
              onPressed: hasNext ? pb.skipToNext : null,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              tooltip: switch (pb.repeat.value) {
                Repeat.off => 'Repeat off',
                Repeat.all => 'Repeat all',
                Repeat.one => 'Repeat this track',
              },
              color: pb.repeat.value == Repeat.off ? null : on,
              onPressed: () => pb.setRepeat(pb.repeat.value.next),
              icon: Icon(pb.repeat.value == Repeat.one ? Icons.repeat_one : Icons.repeat),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ValueListenableBuilder(
            valueListenable: pb.sound,
            builder: (context, s, _) => IconButton(
              tooltip: 'Equalizer',
              color: s.enabled ? on : null,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EqualizerScreen())),
              icon: const Icon(Icons.equalizer),
            ),
          ),
          StreamBuilder<double>(
            stream: pb.player.stream.rate,
            initialData: pb.player.state.rate,
            builder: (context, rate) => PopupMenuButton<double>(
              tooltip: 'Speed',
              initialValue: rate.data,
              onSelected: pb.setSpeed,
              itemBuilder: (_) => [for (final s in playbackSpeeds) PopupMenuItem(value: s, child: Text(speedLabel(s)))],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(speedLabel(rate.data!),
                    style: theme.textTheme.titleSmall?.copyWith(color: rate.data == 1.0 ? null : on)),
              ),
            ),
          ),
          _SleepButton(pb: pb),
          IconButton(
            tooltip: 'Queue',
            onPressed: () => showQueueSheet(context, pb),
            icon: const Icon(Icons.queue_music),
          ),
        ]),
      ]),
    );
  }
}

class _SleepButton extends StatelessWidget {
  const _SleepButton({required this.pb});
  final Playback pb;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      listenable: Listenable.merge([pb.sleepAt, pb.sleepAfterTrack]),
      builder: (context, _) {
        final at = pb.sleepAt.value;
        final active = at != null || pb.sleepAfterTrack.value;
        final button = IconButton(
          tooltip: 'Sleep timer',
          color: active ? on : null,
          onPressed: () => showSleepSheet(context, pb),
          icon: const Icon(Icons.bedtime_outlined),
        );
        if (at == null) return button;
        // Minutes left under the moon.
        return StreamBuilder(
          stream: Stream<void>.periodic(const Duration(seconds: 15)),
          builder: (context, _) {
            final left = at.difference(DateTime.now());
            return Column(mainAxisSize: MainAxisSize.min, children: [
              button,
              Text("${(left.inSeconds / 60).ceil().clamp(0, 999)}'", style: TextStyle(color: on, fontSize: 11)),
            ]);
          },
        );
      },
    );
  }
}

/// Pause the music after a while, or when the current track ends.
void showSleepSheet(BuildContext context, Playback pb) {
  const choices = [15, 30, 45, 60, 90, 120];
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Sleep timer'), subtitle: Text('The music pauses by itself')),
          if (pb.sleepAt.value != null || pb.sleepAfterTrack.value)
            ListTile(
              leading: const Icon(Icons.timer_off_outlined),
              title: const Text('Turn off'),
              onTap: () {
                pb.setSleepTimer(null);
                Navigator.pop(context);
              },
            ),
          for (final m in choices)
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(m < 60 ? 'In $m minutes' : 'In ${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60} min'}'),
              onTap: () {
                pb.setSleepTimer(Duration(minutes: m));
                Navigator.pop(context);
              },
            ),
          ListTile(
            leading: const Icon(Icons.music_off_outlined),
            title: const Text('When this track ends'),
            onTap: () {
              pb.setSleepTimer(null, endOfTrack: true);
              Navigator.pop(context);
            },
          ),
        ]),
      ),
    ),
  );
}

/// Position in the track, draggable.
class MusicSeekBar extends StatefulWidget {
  const MusicSeekBar({super.key, required this.pb});
  final Playback pb;

  @override
  State<MusicSeekBar> createState() => _MusicSeekBarState();
}

class _MusicSeekBarState extends State<MusicSeekBar> {
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
          final style = Theme.of(context).textTheme.bodySmall;
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
                Text(formatDuration(Duration(milliseconds: current.round())), style: style),
                Text(total > 0 ? '−${formatDuration(Duration(milliseconds: (total - current).round()))}' : '',
                    style: style),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
