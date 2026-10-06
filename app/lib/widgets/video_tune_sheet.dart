import 'package:flutter/material.dart';

import '../services/playback.dart';
import '../services/video_tuning.dart';

/// Speed, subtitle look and timing, and sound timing of the playing video.
void showVideoTuneSheet(BuildContext context, Playback pb) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.9,
      builder: (context, scroll) => ValueListenableBuilder<VideoAdjust>(
        valueListenable: pb.adjust,
        builder: (context, a, _) {
          final theme = Theme.of(context);
          Widget header(String text) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              );
          return ListView(
            controller: scroll,
            children: [
              header('Speed'),
              StreamBuilder<double>(
                stream: pb.player.stream.rate,
                initialData: pb.player.state.rate,
                builder: (context, rate) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final s in playbackSpeeds)
                      ChoiceChip(
                        label: Text(speedLabel(s)),
                        selected: (rate.data! - s).abs() < 0.001,
                        onSelected: (_) => pb.player.setRate(s),
                      ),
                  ]),
                ),
              ),
              header('Subtitles'),
              _SliderTile(
                title: 'Size',
                value: a.subtitleScale,
                min: VideoAdjust.minScale,
                max: VideoAdjust.maxScale,
                divisions: 20,
                label: '${(a.subtitleScale * 100).round()}%',
                onChanged: (v) => pb.setAdjust(a.copyWith(subtitleScale: (v * 10).round() / 10)),
              ),
              _SliderTile(
                title: 'Height',
                // Up the slider is up the screen.
                value: (100 - a.subtitlePosition).toDouble(),
                min: 0,
                max: (100 - VideoAdjust.minPosition).toDouble(),
                divisions: 10,
                label: a.subtitlePosition == 100 ? 'Bottom' : '+${100 - a.subtitlePosition}%',
                onChanged: (v) => pb.setAdjust(a.copyWith(subtitlePosition: 100 - v.round())),
              ),
              ListTile(
                title: const Text('Colour'),
                subtitle: const Text('Plain subtitles; styled ones keep their own'),
                trailing: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('White')),
                    ButtonSegment(value: true, label: Text('Yellow')),
                  ],
                  selected: {a.subtitleYellow},
                  onSelectionChanged: (s) => pb.setAdjust(a.copyWith(subtitleYellow: s.first)),
                ),
              ),
              _DelayTile(
                title: 'Subtitle delay',
                hint: 'Plus: subtitles appear later',
                seconds: a.subtitleDelay,
                onChanged: (v) => pb.setAdjust(a.copyWith(subtitleDelay: v)),
              ),
              header('Sound'),
              _DelayTile(
                title: 'Sound delay',
                hint: 'Plus: sound plays later',
                seconds: a.audioDelay,
                onChanged: (v) => pb.setAdjust(a.copyWith(audioDelay: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: OutlinedButton(
                  onPressed: () {
                    pb.player.setRate(1.0);
                    pb.setAdjust(const VideoAdjust());
                  },
                  child: const Text('Reset all'),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(children: [
          SizedBox(width: 72, child: Text(title)),
          Expanded(
            child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
          ),
          SizedBox(width: 56, child: Text(label, textAlign: TextAlign.end)),
        ]),
      );
}

class _DelayTile extends StatelessWidget {
  const _DelayTile({required this.title, required this.hint, required this.seconds, required this.onChanged});

  final String title;
  final String hint;
  final double seconds;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget step(String text, double by) => TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 6)),
          onPressed: () => onChanged(stepDelay(seconds, by)),
          child: Text(text),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title)),
          if (seconds != 0) TextButton(onPressed: () => onChanged(0), child: const Text('Reset')),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          step('−1', -1),
          step('−0.1', -0.1),
          SizedBox(
            width: 80,
            child: Text(delayLabel(seconds), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          step('+0.1', 0.1),
          step('+1', 1),
        ]),
        Text(hint, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
