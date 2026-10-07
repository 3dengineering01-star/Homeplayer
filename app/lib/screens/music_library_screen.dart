import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../services/music_index.dart';
import '../widgets/media_cards.dart';
import '../widgets/track_tile.dart';
import '../widgets/vinyl_art.dart';
import 'jellyfin_actions.dart';
import 'jellyfin_browser.dart';
import 'playlist_picker.dart';
import 'track_list_screen.dart';

/// The order picked on each tab, kept while the app runs.
ArtistSort _artistSort = ArtistSort.name;
AlbumSort _albumSort = AlbumSort.name;
TrackSort _trackSort = TrackSort.title;

/// A music library by artists, albums, tracks and playlists, each sorted as the user picks and
/// filtered by what is typed in the search field.
class MusicLibraryScreen extends StatefulWidget {
  const MusicLibraryScreen({super.key, required this.client, required this.library});

  final JellyfinClient client;
  final JellyfinItem library;

  @override
  State<MusicLibraryScreen> createState() => _MusicLibraryScreenState();
}

typedef _Music = ({List<JellyfinItem> tracks, List<ArtistGroup> artists, List<AlbumGroup> albums});

class _MusicLibraryScreenState extends State<MusicLibraryScreen> with JellyfinActions, SingleTickerProviderStateMixin {
  @override
  JellyfinClient get client => widget.client;

  late final TabController _tabs = TabController(length: 4, vsync: this)..addListener(() => setState(() {}));
  late Future<_Music> _music = _load();
  late Future<List<JellyfinItem>> _playlists = client.playlists();
  final _query = TextEditingController();
  bool _searching = false;

  Future<_Music> _load() async {
    final tracks = await client.musicTracks(widget.library.id);
    return (tracks: tracks, artists: groupByArtist(tracks), albums: groupByAlbum(tracks));
  }

  @override
  void refresh() => setState(() {
    _music = _load();
    _playlists = client.playlists();
  });

  void _refreshPlaylists() => setState(() => _playlists = client.playlists());

  @override
  void dispose() {
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  String get _text => _searching ? _query.text.trim().toLowerCase() : '';

  Widget _sortButton() {
    PopupMenuButton<T> menu<T>(List<T> values, T current, String Function(T) label, void Function(T) pick) =>
        PopupMenuButton<T>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          initialValue: current,
          onSelected: (v) => setState(() => pick(v)),
          itemBuilder: (_) => [for (final v in values) PopupMenuItem(value: v, child: Text(label(v)))],
        );
    return switch (_tabs.index) {
      0 => menu(ArtistSort.values, _artistSort, (s) => s.label, (s) => _artistSort = s),
      1 => menu(AlbumSort.values, _albumSort, (s) => s.label, (s) => _albumSort = s),
      2 => menu(TrackSort.values, _trackSort, (s) => s.label, (s) => _trackSort = s),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Artist, album or track', border: InputBorder.none),
                onChanged: (_) => setState(() {}),
              )
            : Text(widget.library.name),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query.clear();
            }),
          ),
          _sortButton(),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            onSelected: (a) => a(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        JellyfinBrowser(client: client, title: widget.library.name, parentId: widget.library.id),
                  ),
                ),
                child: const ListTile(leading: Icon(Icons.folder_outlined), title: Text('Folders')),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Artists'),
            Tab(text: 'Albums'),
            Tab(text: 'Tracks'),
            Tab(text: 'Playlists'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _withMusic((m) => _artistList(m)),
          _withMusic((m) => _albumGrid(m)),
          _withMusic((m) => _trackList(m)),
          _playlistList(),
        ],
      ),
    );
  }

  Widget _withMusic(Widget Function(_Music) build) => FutureBuilder<_Music>(
    future: _music,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return _Failed(error: snap.error!, onRetry: refresh);
      return RefreshIndicator(
        onRefresh: () async {
          refresh();
          await _music.then((_) {}, onError: (_) {});
        },
        child: build(snap.data!),
      );
    },
  );

  Widget _artistList(_Music m) {
    final q = _text;
    final artists = sortArtists(
      m.artists,
      _artistSort,
    ).where((a) => q.isEmpty || a.name.toLowerCase().contains(q)).toList();
    if (artists.isEmpty) return const _Empty();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: artists.length,
      itemBuilder: (context, i) {
        final a = artists[i];
        final albums = a.albums.where((g) => !g.loose).length;
        return ListTile(
          leading: _RoundCover(client: client, item: a.cover),
          title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if (albums > 0) '$albums ${albums == 1 ? 'album' : 'albums'}',
              '${a.trackCount} ${a.trackCount == 1 ? 'track' : 'tracks'}',
            ].join(' · '),
          ),
          onTap: () => _open(
            TrackListScreen(
              client: client,
              title: a.name,
              subtitle: 'Artist',
              load: () async => a.tracks,
              cover: a.cover,
              byAlbum: true,
            ),
          ),
          onLongPress: () => addToPlaylist(context, client, items: a.tracks),
        );
      },
    );
  }

  Widget _albumGrid(_Music m) {
    final q = _text;
    final albums = sortAlbums(
      m.albums,
      _albumSort,
    ).where((a) => q.isEmpty || '${a.name} ${a.artist}'.toLowerCase().contains(q)).toList();
    if (albums.isEmpty) return const _Empty();
    return LayoutBuilder(
      builder: (context, box) {
        final columns = ((box.maxWidth - 32 + 12) / (180 + 12)).ceil().clamp(2, 8);
        final cell = (box.maxWidth - 32 - 12 * (columns - 1)) / columns;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // A square cover, then two lines of text that grow with the phone's text size.
            mainAxisExtent: cell + 8 + MediaQuery.textScalerOf(context).scale(40),
          ),
          itemCount: albums.length,
          itemBuilder: (context, i) => _AlbumCard(
            client: client,
            album: albums[i],
            onTap: () => _open(
              TrackListScreen(
                client: client,
                title: albums[i].name,
                subtitle: [albums[i].artist, albums[i].year?.toString()].whereType<String>().join(' · '),
                load: () async => albums[i].tracks,
                cover: albums[i].cover,
              ),
            ),
            onLongPress: () => addToPlaylist(context, client, items: albums[i].tracks),
          ),
        );
      },
    );
  }

  Widget _trackList(_Music m) {
    final q = _text;
    final tracks = sortTracks(m.tracks, _trackSort).where((t) => q.isEmpty || trackMatches(t, q)).toList();
    if (tracks.isEmpty) return const _Empty();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: tracks.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => playAll(tracks),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Play ${tracks.length}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => playAll(tracks, shuffle: true),
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Shuffle'),
                  ),
                ),
              ],
            ),
          );
        }
        final t = tracks[i - 1];
        return TrackTile(
          client: client,
          item: t,
          onTap: () => openItem(tracks, t),
          onLongPress: () => itemActions(tracks, t),
        );
      },
    );
  }

  Widget _playlistList() => PlaylistList(client: client, playlists: _playlists, onChanged: _refreshPlaylists);

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _refreshPlaylists();
  }
}

/// The user's playlists with a button for a new one; opening one shows its tracks.
class PlaylistList extends StatelessWidget {
  const PlaylistList({super.key, required this.client, required this.playlists, required this.onChanged});

  final JellyfinClient client;
  final Future<List<JellyfinItem>> playlists;

  /// After a playlist was made, changed or deleted.
  final VoidCallback onChanged;

  Future<void> _create(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await askPlaylistName(context);
    if (name == null) return;
    try {
      await client.createPlaylist(name, const []);
      onChanged();
      messenger.showSnackBar(SnackBar(content: Text('"$name" made. Long-press tracks or albums to add them.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<JellyfinItem>>(
    future: playlists,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return _Failed(error: snap.error!, onRetry: onChanged);
      final list = snap.data!;
      return RefreshIndicator(
        onRefresh: () async => onChanged(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              title: const Text('New playlist'),
              onTap: () => _create(context),
            ),
            for (final p in list)
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox.square(
                    dimension: 48,
                    child: client.imageUrl(p, height: 112) == null
                        ? const NoteTile()
                        : NetImage(
                            url: client.imageUrl(p, height: 112),
                            headers: client.headers,
                            icon: Icons.queue_music,
                          ),
                  ),
                ),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: p.childCount == null ? null : Text(countLabelOf(p.childCount!, 'item')),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TrackListScreen.playlist(client: client, playlist: p),
                    ),
                  );
                  onChanged();
                },
              ),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No playlists yet. Make one here, or long-press a track or an album and choose '
                  '"Add to playlist".',
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// The playlists on their own, for the server's Playlists library.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key, required this.client, required this.title});

  final JellyfinClient client;
  final String title;

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  late Future<List<JellyfinItem>> _playlists = widget.client.playlists();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: PlaylistList(
      client: widget.client,
      playlists: _playlists,
      onChanged: () => setState(() => _playlists = widget.client.playlists()),
    ),
  );
}

class _RoundCover extends StatelessWidget {
  const _RoundCover({required this.client, required this.item});

  final JellyfinClient client;
  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final url = client.imageUrl(item, height: 112);
    return ClipOval(
      child: SizedBox.square(
        dimension: 48,
        child: url == null ? const NoteTile(size: 22) : NetImage(url: url, headers: client.headers, icon: Icons.person),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.client, required this.album, required this.onTap, required this.onLongPress});

  final JellyfinClient client;
  final AlbumGroup album;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = client.imageUrl(album.cover, height: 360);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: url == null
                  ? const NoteTile(size: 40)
                  : NetImage(url: url, headers: client.headers, icon: Icons.album),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
            child: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => ListView(
    children: const [
      Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('Nothing here')),
      ),
    ],
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(describeError(error), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
