import 'package:flutter/material.dart';

import '../api/jellyfin.dart';
import '../services/music_folders.dart';
import '../services/search_index.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/media_cards.dart';
import '../widgets/track_tile.dart';
import 'jellyfin_actions.dart';
import 'playlist_picker.dart';

/// A music folder as it is on disk: Play and Shuffle for everything in it, its folders, then its
/// tracks. A folder opens on a page of its own, so Back goes up a level.
class MusicFolderView extends StatefulWidget {
  const MusicFolderView({super.key, required this.client, required this.folder});

  final JellyfinClient client;
  final MusicFolder folder;

  @override
  State<MusicFolderView> createState() => _MusicFolderViewState();
}

class _MusicFolderViewState extends State<MusicFolderView> with JellyfinActions {
  @override
  JellyfinClient get client => widget.client;

  @override
  void refresh() => setState(() {});

  void _open(MusicFolder folder) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(folder.name)),
        body: MusicFolderView(client: client, folder: folder),
      ),
    ),
  );

  Future<void> _folderActions(MusicFolder folder) async {
    final tracks = folder.allTracks;
    final actions = <SheetAction>[
      (icon: Icons.play_arrow, label: 'Play', run: () => playAll(tracks)),
      (icon: Icons.shuffle, label: 'Shuffle', run: () => playAll(tracks, shuffle: true)),
      (icon: Icons.playlist_add, label: 'Add to playlist', run: () => addToPlaylist(context, client, items: tracks)),
      (icon: Icons.save_alt, label: "Save to phone's Music", run: () => saveToPhone(tracks)),
    ];
    final picked = await showModalBottomSheet<SheetAction>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(folder.name, style: Theme.of(c).textTheme.titleMedium), subtitle: Text(_count(folder))),
            for (final a in actions)
              ListTile(leading: Icon(a.icon), title: Text(a.label), onTap: () => Navigator.pop(c, a)),
          ],
        ),
      ),
    );
    await picked?.run();
  }

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final all = folder.allTracks;
    if (all.isEmpty) return const Center(child: Text('Nothing here'));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => playAll(all),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Play ${all.length}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => playAll(all, shuffle: true),
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle'),
                ),
              ),
            ],
          ),
        ),
        for (final f in folder.folders)
          ListTile(
            leading: _FolderCover(client: client, folder: f),
            title: Text(f.name),
            subtitle: Text(_count(f)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(f),
            onLongPress: () => _folderActions(f),
          ),
        for (final t in folder.tracks)
          TrackTile(
            client: client,
            item: t,
            onTap: () => openItem(folder.tracks, t),
            onLongPress: () => itemActions(folder.tracks, t),
          ),
      ],
    );
  }
}

/// "3 folders · 42 tracks".
String _count(MusicFolder f) {
  final n = f.trackCount;
  return [
    if (f.folders.isNotEmpty) '${f.folders.length} ${f.folders.length == 1 ? 'folder' : 'folders'}',
    '$n ${n == 1 ? 'track' : 'tracks'}',
  ].join(' · ');
}

/// A folder's picture: a cover from inside it with a folder mark, or just the folder.
class _FolderCover extends StatelessWidget {
  const _FolderCover({required this.client, required this.folder});

  final JellyfinClient client;
  final MusicFolder folder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = folder.cover;
    final url = cover == null ? null : client.imageUrl(cover, height: 112);
    return SizedBox.square(
      dimension: 48,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: url == null
                  ? ColoredBox(
                      color: scheme.secondaryContainer,
                      child: Icon(Icons.folder, color: scheme.onSecondaryContainer),
                    )
                  : NetImage(url: url, headers: client.headers, icon: Icons.folder),
            ),
          ),
          if (url != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(6)),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.folder, size: 14, color: scheme.onSecondaryContainer),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// While searching: folders named so or holding a matching track, with where they are.
class MusicFolderHits extends StatelessWidget {
  const MusicFolderHits({super.key, required this.client, required this.hits, required this.query});

  final JellyfinClient client;
  final List<Hit<MusicFolder>> hits;
  final String query;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      for (final h in hits)
        ListTile(
          leading: _FolderCover(client: client, folder: h.group),
          title: HighlightedText(h.group.name, query: query),
          subtitle: HighlightedText(
            h.inside.isEmpty
                ? h.group.path
                : 'Has: ${h.inside.take(3).map((t) => t.name).join(', ')}'
                      '${h.inside.length > 3 ? ' and ${h.inside.length - 3} more' : ''}',
            query: query,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(h.group.name)),
                body: MusicFolderView(client: client, folder: h.group),
              ),
            ),
          ),
        ),
    ],
  );
}
