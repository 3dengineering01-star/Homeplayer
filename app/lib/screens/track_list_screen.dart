import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../services/music_index.dart';
import '../widgets/media_cards.dart';
import '../widgets/track_tile.dart';
import '../widgets/vinyl_art.dart';
import 'jellyfin_actions.dart';
import 'playlist_picker.dart';

/// An album, an artist or a playlist: a cover, the name, Play and Shuffle, and the tracks.
class TrackListScreen extends StatefulWidget {
  const TrackListScreen({
    super.key,
    required this.client,
    required this.title,
    required this.load,
    this.subtitle,
    this.cover,
    this.byAlbum = false,
    this.playlist,
  });

  /// An album from the server.
  TrackListScreen.album({super.key, required this.client, required JellyfinItem album})
    : title = album.name,
      subtitle = [album.albumArtist, album.year?.toString()].whereType<String>().join(' · '),
      load = (() => client.albumTracks(album.id)),
      cover = album,
      byAlbum = false,
      playlist = null;

  /// An artist from the server's search, with their tracks album by album.
  TrackListScreen.artist({super.key, required this.client, required JellyfinItem artist})
    : title = artist.name,
      subtitle = null,
      load = (() async => [for (final a in groupByArtist(await client.artistTracks(artist.id))) ...a.tracks]),
      cover = artist,
      byAlbum = true,
      playlist = null;

  /// A playlist: tracks can be taken out, and the playlist deleted.
  TrackListScreen.playlist({super.key, required this.client, required JellyfinItem this.playlist})
    : title = playlist.name,
      subtitle = 'Playlist',
      load = (() => client.playlistItems(playlist.id)),
      cover = playlist,
      byAlbum = false;

  final JellyfinClient client;
  final String title;
  final String? subtitle;
  final Future<List<JellyfinItem>> Function() load;

  /// The item whose picture heads the page; else the first track's.
  final JellyfinItem? cover;

  /// A heading over each album's tracks, for an artist.
  final bool byAlbum;
  final JellyfinItem? playlist;

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> with JellyfinActions {
  @override
  JellyfinClient get client => widget.client;

  late Future<List<JellyfinItem>> _tracks = widget.load();

  @override
  void refresh() => setState(() => _tracks = widget.load());

  Future<void> _remove(JellyfinItem track) async {
    final entry = track.playlistEntryId;
    if (entry == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await client.removeFromPlaylist(widget.playlist!.id, [entry]);
      refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _deletePlaylist() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('"${widget.title}". The music itself stays on the server.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await client.deletePlaylist(widget.playlist!.id);
      nav.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.playlist != null)
            PopupMenuButton<VoidCallback>(
              tooltip: 'More',
              onSelected: (a) => a(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _deletePlaylist,
                  child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete playlist')),
                ),
              ],
            ),
        ],
      ),
      body: FutureBuilder<List<JellyfinItem>>(
        future: _tracks,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(describeError(snap.error!), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }
          final tracks = snap.data!;
          final rows = <Widget>[
            _Header(
              client: client,
              title: widget.title,
              subtitle: widget.subtitle,
              // A playlist or an artist without a picture shows its first track's cover.
              cover: widget.cover != null && client.imageUrl(widget.cover!) != null ? widget.cover : tracks.firstOrNull,
              tracks: tracks,
              onPlay: () => playAll(tracks),
              onShuffle: () => playAll(tracks, shuffle: true),
              onSave: tracks.any((t) => t.type == 'Audio') ? () => saveToPhone(tracks) : null,
              onAddAll: widget.playlist != null || tracks.isEmpty
                  ? null
                  : () => addToPlaylist(context, client, items: tracks),
            ),
            if (tracks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    widget.playlist != null
                        ? 'Empty. Long-press a track or an album and choose "Add to playlist".'
                        : 'Nothing here',
                  ),
                ),
              ),
          ];
          String? album;
          for (final t in tracks) {
            if (widget.byAlbum && (t.album ?? '') != album) {
              album = t.album ?? '';
              rows.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    album.isEmpty ? 'Other tracks' : album,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              );
            }
            rows.add(
              TrackTile(
                client: client,
                item: t,
                onTap: () => openItem(tracks, t),
                onLongPress: () => itemActions(
                  tracks,
                  t,
                  extra: [
                    if (widget.playlist != null && t.playlistEntryId != null)
                      (icon: Icons.playlist_remove, label: 'Remove from playlist', run: () => _remove(t)),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              refresh();
              await _tracks.then((_) {}, onError: (_) {});
            },
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: rows),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.client,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.tracks,
    required this.onPlay,
    required this.onShuffle,
    required this.onAddAll,
    required this.onSave,
  });

  final JellyfinClient client;
  final String title;
  final String? subtitle;
  final JellyfinItem? cover;
  final List<JellyfinItem> tracks;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback? onAddAll;

  /// Saves the tracks into the phone's Music folder; null when there are none.
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = cover == null ? null : client.imageUrl(cover!, height: 360);
    final length = tracks.fold(Duration.zero, (sum, t) => sum + (t.runTime ?? Duration.zero));
    final facts = [
      '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
      if (length > Duration.zero) runTimeLabel(length),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox.square(
                  dimension: 120,
                  child: url == null
                      ? const NoteTile(size: 48)
                      : NetImage(url: url, headers: client.headers, icon: Icons.album),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
                    Text(facts, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: tracks.isEmpty ? null : onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: tracks.isEmpty ? null : onShuffle,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle'),
                ),
              ),
              if (onAddAll != null)
                IconButton(tooltip: 'Add to playlist', onPressed: onAddAll, icon: const Icon(Icons.playlist_add)),
              if (onSave != null)
                IconButton(tooltip: "Save to phone's Music", onPressed: onSave, icon: const Icon(Icons.save_alt)),
            ],
          ),
        ],
      ),
    );
  }
}
