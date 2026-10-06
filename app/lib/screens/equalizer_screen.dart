import 'package:flutter/material.dart';

import '../services/audio_effects.dart';
import '../services/playback.dart';

/// Ten-band equalizer with presets, and volume levelling, for music.
class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pb = Playback.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Equalizer')),
      body: ListenableBuilder(
        listenable: Listenable.merge([pb.sound, pb.equalizerWorks]),
        builder: (context, _) {
          final s = pb.sound.value;
          final theme = Theme.of(context);
          final preset = s.preset;
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            SwitchListTile(
              title: const Text('Equalizer'),
              subtitle: const Text('For music; videos play as they are'),
              value: s.enabled,
              onChanged: (on) => pb.setSound(s.copyWith(enabled: on)),
            ),
            if (!pb.equalizerWorks.value)
              ListTile(
                leading: Icon(Icons.warning_amber, color: theme.colorScheme.error),
                title: const Text('The player on this phone could not turn the equalizer on'),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final e in eqPresets.entries)
                  ChoiceChip(
                    label: Text(e.key),
                    selected: preset == e.key,
                    onSelected: (_) => pb.setSound(s.copyWith(enabled: true, gains: e.value)),
                  ),
                if (preset == null) const ChoiceChip(label: Text('Custom'), selected: true),
              ]),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: s.enabled ? 1 : 0.4,
              child: SizedBox(
                height: 260,
                child: Row(children: [
                  for (final (i, hz) in eqBands.indexed)
                    Expanded(
                      child: Column(children: [
                        Text('${s.gains[i] > 0 ? '+' : ''}${s.gains[i].round()}', style: theme.textTheme.labelSmall),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              value: s.gains[i],
                              min: -eqMaxGain,
                              max: eqMaxGain,
                              divisions: 24,
                              // The sound changes when the finger lifts: mpv rebuilds its
                              // filters on each change, which would crackle while dragging.
                              onChanged: (v) {
                                final gains = [...s.gains]..[i] = v;
                                pb.sound.value = s.copyWith(enabled: true, gains: gains);
                              },
                              onChangeEnd: (_) => pb.setSound(pb.sound.value),
                            ),
                          ),
                        ),
                        Text(bandLabel(hz), style: theme.textTheme.labelSmall),
                      ]),
                    ),
                ]),
              ),
            ),
            const Divider(height: 32),
            ListTile(
              title: const Text('Volume levelling'),
              subtitle: const Text('Evens out loud and quiet tracks using their ReplayGain tags'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ReplayGain>(
                segments: [for (final r in ReplayGain.values) ButtonSegment(value: r, label: Text(r.label))],
                selected: {s.replayGain},
                onSelectionChanged: (v) => pb.setSound(s.copyWith(replayGain: v.first)),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
