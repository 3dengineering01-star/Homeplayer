import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../api/common.dart';
import '../services/playback.dart';
import '../services/track_choice.dart';

/// Audio and subtitle tracks of the playing file. The choice is remembered for the next files.
void showTrackSheet(BuildContext context, Playback pb) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StreamBuilder<Track>(
      stream: pb.player.stream.track,
      initialData: pb.player.state.track,
      builder: (context, selected) => FutureBuilder(
        // Re-read on every track change; media_kit says 'auto' for tracks mpv picked itself.
        key: ValueKey(selected.data),
        future: pb.activeTrackIds(),
        builder: (context, ids) {
          final tracks = pb.player.state.tracks;
          final audio = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
          final subs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
          final current = selected.data!;
          final audioId = current.audio.id == 'auto' ? ids.data?.audio : current.audio.id;
          final subtitleId = current.subtitle.id == 'auto' ? ids.data?.subtitle : current.subtitle.id;
          final theme = Theme.of(context);
          Widget header(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          );
          Widget check(bool on) => on ? const Icon(Icons.check) : const SizedBox(width: 24);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            builder: (context, scroll) => ListView(
              controller: scroll,
              children: [
                header('Audio'),
                if (audio.isEmpty) const ListTile(title: Text('No audio')),
                for (final t in audio)
                  ListTile(
                    leading: check(audioId == t.id),
                    title: Text(audioLabel(t)),
                    subtitle: canDecodeAudio(t.codec) ? null : const Text('Not supported on this phone'),
                    enabled: canDecodeAudio(t.codec),
                    onTap: () => pb.selectAudio(t),
                  ),
                header('Subtitles'),
                ListTile(
                  leading: check(subtitleId == 'no'),
                  title: const Text('Off'),
                  onTap: () => pb.selectSubtitle(SubtitleTrack.no()),
                ),
                for (final t in subs)
                  ListTile(
                    leading: check(subtitleId == t.id),
                    title: Text(subtitleLabel(t)),
                    onTap: () => pb.selectSubtitle(t),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    ),
  );
}
