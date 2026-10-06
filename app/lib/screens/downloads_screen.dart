import 'dart:io';

import 'package:flutter/material.dart';

import '../api/common.dart';
import '../services/downloads.dart';
import '../services/playback.dart';
import 'player_screen.dart';

/// Everything downloaded to the phone, by season or album; plays without a connection.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final Downloads _downloads = Downloads.instance;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _downloads.init().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  /// Plays [entry] and the finished downloads of its group after it; a video started earlier
  /// can go on from where it stopped.
  Future<void> _play(List<DownloadEntry> group, DownloadEntry entry) async {
    final done = group.where((e) => e.state == DownloadState.done && e.isVideo == entry.isVideo).toList();
    final nav = Navigator.of(context);
    Duration? startAt;
    if (entry.isVideo && !entry.watched && entry.position > const Duration(seconds: 30)) {
      startAt = await showModalBottomSheet<Duration>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text('Resume from ${formatDuration(entry.position)}'),
              onTap: () => Navigator.pop(context, entry.position),
            ),
            ListTile(
              leading: const Icon(Icons.replay),
              title: const Text('Start over'),
              onTap: () => Navigator.pop(context, Duration.zero),
            ),
          ]),
        ),
      );
      if (startAt == null) return;
    }
    await Playback.instance.start([for (final e in done) _downloads.toPlayItem(e)], done.indexOf(entry), startAt: startAt);
    await nav.push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
    final pb = Playback.instance;
    if (pb.currentItem?.isVideo ?? false) await pb.stop();
  }

  Future<void> _delete(DownloadEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(e.state == DownloadState.done ? 'Delete download?' : 'Cancel download?'),
        content: Text(e.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _downloads.remove(e.id);
  }

  Widget? _status(BuildContext context, DownloadEntry e) => switch (e.state) {
        DownloadState.done => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text([
              if (e.subtitle != null) e.subtitle!,
              sizeLabel(e.size),
              if (e.watched) 'Watched',
              if (e.unsynced) 'Not on the server yet',
            ].join(' · ')),
            if (e.isVideo && !e.watched && e.position > Duration.zero && e.duration > Duration.zero)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(
                    value: (e.position.inMilliseconds / e.duration.inMilliseconds).clamp(0.0, 1.0),
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(2)),
              ),
          ]),
        DownloadState.queued => const Text('Waiting...'),
        DownloadState.paused => const Text('Paused, continues when the connection is back'),
        DownloadState.failed => Text('Failed. Delete it and download again.',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        DownloadState.running => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${(e.progress * 100).round()}%${e.size > 0 ? ' of ${sizeLabel(e.size)}' : ''}'),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: e.progress, minHeight: 3, borderRadius: BorderRadius.circular(2)),
            ),
          ]),
      };

  Widget _thumb(DownloadEntry e) {
    final fallback = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(e.isVideo ? Icons.movie : Icons.music_note, size: 24),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox.square(
        dimension: 56,
        child: e.hasArtwork
            ? Image.file(File(_downloads.pathOf(e.artworkFile)), fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback)
            : fallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<DownloadEntry>>(
      valueListenable: _downloads.entries,
      builder: (context, entries, _) {
        final total = entries.where((e) => e.state == DownloadState.done).fold<int>(0, (s, e) => s + e.size);
        final groups = <String, List<DownloadEntry>>{};
        for (final e in entries) {
          groups.putIfAbsent(e.group ?? '', () => []).add(e);
        }
        return Scaffold(
          appBar: AppBar(title: Text(total > 0 ? 'Downloads · ${sizeLabel(total)}' : 'Downloads')),
          body: !_ready
              ? const Center(child: CircularProgressIndicator())
              : entries.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Nothing downloaded yet.\nLong-press a movie, an episode, a season or an album to download it.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(children: [
                      for (final MapEntry(key: name, value: group) in groups.entries) ...[
                        if (name.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Text(name,
                                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
                          ),
                        for (final e in group)
                          ListTile(
                            leading: _thumb(e),
                            title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: _status(context, e),
                            onTap: e.state == DownloadState.done ? () => _play(group, e) : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete',
                              onPressed: () => _delete(e),
                            ),
                          ),
                      ],
                    ]),
        );
      },
    );
  }
}
