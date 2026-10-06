import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../api/common.dart';
import '../services/playback.dart';
import '../services/quality.dart';
import '../services/track_choice.dart';

/// Plays the current video again in [q] from where it is, closing the sheet first.
Future<void> _switchQuality(BuildContext context, Playback pb, VideoQuality q) async {
  final messenger = ScaffoldMessenger.of(context);
  Navigator.pop(context);
  messenger.showSnackBar(SnackBar(content: Text(q.isAuto ? 'Measuring the connection...' : 'Switching to ${q.label}...')));
  try {
    await pb.changeQuality(q);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
  }
}

/// Audio and subtitle tracks of the playing file, and its quality when the server can
/// convert it. Track choices are remembered for the next files; quality is for this video only.
void showTrackSheet(BuildContext context, Playback pb) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // The sheet stays put while its content follows track changes, so picking a track does
    // not scroll the list back to the top.
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.9,
      builder: (context, scroll) => StreamBuilder<Track>(
        stream: pb.player.stream.track,
        initialData: pb.player.state.track,
        builder: (context, selected) => FutureBuilder(
          // Re-read on every track change; media_kit says 'auto' for tracks mpv picked itself.
          future: pb.activeTrackIds(),
          builder: (context, ids) {
            final tracks = pb.player.state.tracks;
            final audio = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
            final subs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
            final audioLabels = distinctLabels([for (final t in audio) audioLabel(t)]);
            final subtitleLabels = distinctLabels([for (final t in subs) subtitleLabel(t)]);
            final current = selected.data!;
            final audioId = current.audio.id == 'auto' ? ids.data?.audio : current.audio.id;
            final subtitleId = current.subtitle.id == 'auto' ? ids.data?.subtitle : current.subtitle.id;
            final item = pb.currentItem;
            final theme = Theme.of(context);
            Widget header(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            );
            Widget check(bool on) => on ? const Icon(Icons.check) : const SizedBox(width: 24);
            return ListView(
              controller: scroll,
              children: [
                header('Audio'),
                if (audio.isEmpty) const ListTile(title: Text('No audio')),
                for (final (i, t) in audio.indexed)
                  ListTile(
                    leading: check(audioId == t.id),
                    title: Text(audioLabels[i]),
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
                for (final (i, t) in subs.indexed)
                  ListTile(
                    leading: check(subtitleId == t.id),
                    title: Text(subtitleLabels[i]),
                    onTap: () => pb.selectSubtitle(t),
                  ),
                // Last: tracks are picked far more often than quality.
                if (item?.withQuality != null) ...[
                  header('Quality'),
                  ListTile(
                    dense: true,
                    title: Text(item!.convertedTo == null
                        ? 'Now: the original file'
                        : 'Now: converted to ${bitrateLabel(item.convertedTo!)}'),
                  ),
                  for (final q in VideoQuality.choices)
                    ListTile(
                      leading: check(item.convertedTo == null ? q.isOriginal : q.cap == item.convertedTo),
                      title: Text(q.label),
                      subtitle: q.isAuto ? const Text('Measure the connection now') : null,
                      onTap: () => _switchQuality(context, pb, q),
                    ),
                ],
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    ),
  );
}
