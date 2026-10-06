import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../services/playback.dart';
import '../widgets/async_list.dart';
import 'player_screen.dart';

/// Libraries at the top level, then any folder: series, season, album...
class JellyfinBrowser extends StatefulWidget {
  const JellyfinBrowser({super.key, required this.client, required this.title, this.parentId});

  final JellyfinClient client;
  final String title;
  final String? parentId;

  @override
  State<JellyfinBrowser> createState() => _JellyfinBrowserState();
}

class _JellyfinBrowserState extends State<JellyfinBrowser> {
  /// Bumped to reload the list, e.g. to show new progress after watching.
  int _generation = 0;

  JellyfinClient get client => widget.client;

  IconData _icon(JellyfinItem item) => switch (item.type) {
        'CollectionFolder' || 'UserView' => Icons.folder,
        'MusicAlbum' || 'Audio' => Icons.album,
        'MusicArtist' => Icons.person,
        _ => item.isFolder ? Icons.folder : Icons.movie,
      };

  /// Resolution of the version the user asked to play from now on, e.g. "1080p".
  static const _versionKey = 'version_resolution';

  /// [pickVersion] shows the version list even when a remembered resolution would pick one.
  Future<void> _tap(List<JellyfinItem> items, JellyfinItem item, {bool pickVersion = false}) async {
    final nav = Navigator.of(context);
    if (item.isFolder || !item.isPlayable) {
      await nav.push(MaterialPageRoute(
          builder: (_) => JellyfinBrowser(client: client, title: item.name, parentId: item.id)));
      if (mounted) setState(() => _generation++);
      return;
    }

    // Several files of one movie: the user picks, e.g. 1080p instead of 4K on mobile data.
    String? versionId;
    if (item.versionCount > 1) {
      final versions = await _busy(client.versions(item).onError((e, _) {
        debugPrint('homeplay versions failed for ${item.name}: $e');
        return <MediaVersion>[];
      }));
      if (versions.length > 1) {
        final prefs = await SharedPreferences.getInstance();
        final remembered = pickVersion ? null : chooseVersion(versions, prefs.getString(_versionKey));
        if (remembered != null) {
          versionId = remembered.id;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Playing ${remembered.name.isNotEmpty ? remembered.name : remembered.resolution}. '
                  'Long-press it in the list to choose another version.'),
              duration: const Duration(seconds: 4),
            ));
          }
        } else {
          // Long press: the box shows whether a resolution is remembered, and clearing it forgets
          // it. Otherwise it is ticked only when nothing is remembered yet, so a movie without
          // the remembered resolution does not replace it unless asked to.
          final saved = prefs.getString(_versionKey);
          final choice = await _askVersion(versions, remember: pickVersion ? saved != null : saved == null);
          if (choice == null) return;
          versionId = choice.version.id;
          final resolution = choice.version.resolution;
          if (choice.remember && resolution != null) {
            await prefs.setString(_versionKey, resolution);
          } else if (!choice.remember && pickVersion) {
            await prefs.remove(_versionKey);
          }
        }
      }
    }

    Duration? startAt;
    if (item.isVideo && !item.played && item.resumePosition > const Duration(seconds: 30)) {
      final choice = await _askResume(item.resumePosition);
      if (choice == null) return;
      startAt = choice;
    }

    // Episodes and tracks play through their season or album; a movie plays on its own.
    final playable = item.type == 'Episode' || item.type == 'Audio'
        ? items.where((i) => i.type == item.type).toList()
        : [item];

    if (!mounted) return;
    final queue = await _busy(Future.wait(playable.map((i) {
      final version = i == item ? versionId : null;
      return client.resolve(i, versionId: version).onError((e, _) {
        debugPrint('homeplay PlaybackInfo failed for ${i.name}: $e');
        return client.toPlayItem(i, versionId: version);
      });
    })));
    await Playback.instance.start(queue, playable.indexOf(item), startAt: startAt);
    await nav.push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
    // The pop completes before the player screen is disposed, so end a video here and wait
    // for its stop report; otherwise the reload would show the previous resume point.
    final pb = Playback.instance;
    if (pb.currentItem?.isVideo ?? false) await pb.stop();
    await pb.reportsSent;
    if (mounted) setState(() => _generation++);
  }

  /// A spinner over the screen while the server answers.
  Future<T> _busy<T>(Future<T> work) async {
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      return await work;
    } finally {
      nav.pop();
    }
  }

  /// The chosen file and whether to pick its resolution from now on; null when dismissed.
  Future<({MediaVersion version, bool remember})?> _askVersion(List<MediaVersion> versions, {required bool remember}) =>
      showModalBottomSheet<({MediaVersion version, bool remember})>(
        context: context,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Version',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                ),
                for (final v in versions)
                  ListTile(
                    leading: const Icon(Icons.movie_outlined),
                    title: Text(v.name.isNotEmpty ? v.name : v.details),
                    subtitle: v.name.isNotEmpty && v.details.isNotEmpty ? Text(v.details) : null,
                    onTap: () => Navigator.pop(context, (version: v, remember: remember)),
                  ),
                CheckboxListTile(
                  value: remember,
                  onChanged: (on) => setSheetState(() => remember = on ?? false),
                  title: const Text('Remember my choice'),
                  subtitle: const Text('Next time play this resolution without asking'),
                ),
              ]),
            ),
          ),
        ),
      );

  /// Duration.zero to start over, the resume point to continue, null when dismissed.
  Future<Duration?> _askResume(Duration position) => showModalBottomSheet<Duration>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text('Resume from ${formatDuration(position)}'),
              onTap: () => Navigator.pop(context, position),
            ),
            ListTile(
              leading: const Icon(Icons.replay),
              title: const Text('Start over'),
              onTap: () => Navigator.pop(context, Duration.zero),
            ),
          ]),
        ),
      );

  Widget? _subtitle(JellyfinItem item) {
    final text = item.subtitle;
    final progress = item.played ? null : item.progress;
    if ((text == null || text.isEmpty) && progress == null) return null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (text != null && text.isNotEmpty) Text(text),
      if (progress != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: LinearProgressIndicator(value: progress, minHeight: 3, borderRadius: BorderRadius.circular(2)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.parentId;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: AsyncList<JellyfinItem>(
        key: ValueKey(_generation),
        load: () => id == null ? client.views() : client.children(id),
        itemBuilder: (context, items, i) {
          final item = items[i];
          return ListTile(
            leading: ArtThumb(
              url: client.imageUrl(item, height: 168),
              headers: client.headers,
              icon: _icon(item),
              aspect: item.imageAspect,
            ),
            title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: _subtitle(item),
            trailing: !item.isPlayable
                ? null
                : item.played
                    ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, semanticLabel: 'Watched')
                    : const Icon(Icons.play_arrow),
            onTap: () => _tap(items, item),
            onLongPress: item.versionCount > 1 ? () => _tap(items, item, pickVersion: true) : null,
          );
        },
      ),
    );
  }
}
