import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../services/downloads.dart';
import '../services/playback.dart';
import '../services/quality.dart';
import 'item_details_screen.dart';
import 'jellyfin_browser.dart';
import 'library_screen.dart';
import 'photo_viewer.dart';
import 'player_screen.dart';

/// The page for a Jellyfin folder: a series has its details page, a movie or show library its
/// poster grid, anything else (seasons, albums, home videos) its list.
Widget jellyfinPage(JellyfinClient client, JellyfinItem item) {
  if (item.type == 'Series' || item.type == 'Movie') return ItemDetailsScreen(client: client, item: item);
  final types = posterTypes(item.collectionType);
  if (types != null && (item.type == 'CollectionFolder' || item.type == 'UserView')) {
    return LibraryScreen(client: client, library: item, types: types);
  }
  return JellyfinBrowser(client: client, title: item.name, parentId: item.id);
}

/// Opening, playing and the long-press menu of Jellyfin items, shared by every Jellyfin screen.
mixin JellyfinActions<T extends StatefulWidget> on State<T> {
  JellyfinClient get client;

  /// Called after returning from a page or the player: progress and played marks may have changed.
  void refresh();

  IconData itemIcon(JellyfinItem item) => switch (item.type) {
        'CollectionFolder' || 'UserView' => Icons.folder,
        'MusicAlbum' || 'Audio' => Icons.album,
        'MusicArtist' => Icons.person,
        _ => item.isFolder ? Icons.folder : Icons.movie,
      };

  /// Resolution of the version the user asked to play from now on, e.g. "1080p".
  static const _versionKey = 'version_resolution';

  /// Opens a folder, a series or a library on its page, shows photos, plays the rest. With
  /// [details], a movie opens its page instead of playing. [pickVersion] shows the version list
  /// even when a remembered resolution would pick one.
  Future<void> openItem(List<JellyfinItem> items, JellyfinItem item,
      {bool pickVersion = false, bool details = false}) async {
    final nav = Navigator.of(context);
    if (item.isPhoto) {
      final photos = items.where((i) => i.isPhoto).toList();
      await nav.push(MaterialPageRoute(
          builder: (_) => PhotoViewer(client: client, photos: photos, initial: photos.indexOf(item))));
      return;
    }
    if (item.isFolder || !item.isPlayable || (details && item.type == 'Movie')) {
      await nav.push(MaterialPageRoute(builder: (_) => jellyfinPage(client, item)));
      if (mounted) refresh();
      return;
    }

    // Several files of one movie: the user picks, e.g. 1080p instead of 4K on mobile data.
    String? versionId;
    if (item.versionCount > 1) {
      final versions = await busy(client.versions(item).onError((e, _) {
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

    // An episode on its own (from the home screen) plays on through its season.
    var around = items;
    final seriesId = item.seriesId, seasonId = item.seasonId;
    if (item.type == 'Episode' && items.where((i) => i.type == 'Episode').length == 1 && seriesId != null && seasonId != null) {
      try {
        final season = await busy(client.episodes(seriesId, seasonId));
        final at = season.indexWhere((e) => e.id == item.id);
        if (at >= 0) around = [...season]..[at] = item;
      } catch (e) {
        debugPrint('homeplay season of ${item.name} not loaded: $e');
      }
    }

    // Episodes and tracks play through their season or album; a movie plays on its own.
    final playable = item.type == 'Episode' || item.type == 'Audio'
        ? around.where((i) => i.type == item.type).toList()
        : [item];

    if (!mounted) return;
    final queue = await busy(() async {
      // One decision for the whole queue: the setting for this network, measured once for Auto.
      final cap = playable.any((i) => i.isVideo) ? await client.capNow(await QualitySettings.current()) : null;
      return Future.wait(playable.map((i) {
        final version = i == item ? versionId : null;
        return client.resolve(i, versionId: version, cap: cap).onError((e, _) {
          debugPrint('homeplay PlaybackInfo failed for ${i.name}: $e');
          return client.toPlayItem(i, versionId: version);
        });
      }));
    }());
    await Playback.instance.start(queue, playable.indexOf(item), startAt: startAt);
    await nav.push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
    // The pop completes before the player screen is disposed, so end a video here and wait
    // for its stop report; otherwise the reload would show the previous resume point.
    final pb = Playback.instance;
    if (pb.currentItem?.isVideo ?? false) await pb.stop();
    await pb.reportsSent;
    if (mounted) refresh();
  }

  /// Long press: download (a single item, or everything playable in a folder), or pick a version.
  Future<void> itemActions(List<JellyfinItem> items, JellyfinItem item) async {
    final downloads = Downloads.instance;
    await downloads.init();
    if (!mounted) return;
    final saved = downloads.find(item.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (item.type == 'Audio' || item.type == 'MusicAlbum') ...[
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Play next'),
              onTap: () => Navigator.pop(context, 'next'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to queue'),
              onTap: () => Navigator.pop(context, 'queue'),
            ),
          ],
          if (item.isPlayable && saved == null)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Download'),
              subtitle: const Text('To watch or listen without a connection'),
              onTap: () => Navigator.pop(context, 'download'),
            ),
          if (saved != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(saved.state == DownloadState.done ? 'Delete download' : 'Cancel download'),
              subtitle: saved.size > 0 ? Text(sizeLabel(saved.size)) : null,
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          if (item.isFolder)
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Download all'),
              subtitle: const Text('Every episode, track or video inside'),
              onTap: () => Navigator.pop(context, 'all'),
            ),
          if (item.versionCount > 1)
            ListTile(
              leading: const Icon(Icons.movie_filter_outlined),
              title: const Text('Choose version'),
              onTap: () => Navigator.pop(context, 'version'),
            ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'next' || 'queue':
        final List<PlayItem> tracks;
        try {
          tracks = await busy(() async {
            final all = item.isFolder ? await client.playableDescendants(item.id) : [item];
            final audio = all.where((i) => i.type == 'Audio');
            return Future.wait(audio.map((i) => client.resolve(i).onError((e, _) => client.toPlayItem(i))));
          }());
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
          return;
        }
        final pb = Playback.instance;
        final wasPlaying = pb.currentItem != null && !pb.currentItem!.isVideo;
        action == 'next' ? await pb.playNext(tracks) : await pb.addToQueue(tracks);
        messenger.showSnackBar(SnackBar(
            content: Text(!wasPlaying
                ? 'Playing'
                : action == 'next'
                    ? 'Plays next'
                    : 'Added to the queue')));
      case 'version':
        await openItem(items, item, pickVersion: true);
      case 'delete':
        await downloads.remove(item.id);
      case 'download':
        await downloads.add(client, [item], group: item.seriesName ?? item.album ?? item.name);
        messenger.showSnackBar(const SnackBar(content: Text('Downloading. See Downloads on the server list.')));
      case 'all':
        final List<JellyfinItem> all;
        try {
          all = await busy(client.playableDescendants(item.id));
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
          return;
        }
        final fresh = all.where((i) => downloads.find(i.id) == null).toList();
        if (!mounted) return;
        if (fresh.isEmpty) {
          messenger.showSnackBar(const SnackBar(content: Text('Everything here is already downloaded')));
          return;
        }
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Download ${fresh.length} ${fresh.length == 1 ? 'item' : 'items'}?'),
            content: Text('From "${item.name}". They download in the background, also with the app closed.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Download')),
            ],
          ),
        );
        if (ok != true) return;
        await downloads.add(client, fresh, group: item.name);
        messenger.showSnackBar(SnackBar(content: Text('Downloading ${fresh.length}. See Downloads on the server list.')));
    }
  }

  /// A spinner over the screen while the server answers.
  Future<R> busy<R>(Future<R> work) async {
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
}
