import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../services/music_folders.dart';
import '../services/music_index.dart';
import '../services/search_index.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/media_cards.dart';
import '../widgets/track_tile.dart';
import '../widgets/vinyl_art.dart';
import 'jellyfin_actions.dart';
import 'music_folder_view.dart';
import 'playlist_picker.dart';
import 'track_list_screen.dart';

/// The order picked on each tab, kept while the app runs.
ArtistSort _artistSort = ArtistSort.name;
AlbumSort _albumSort = AlbumSort.name;
TrackSort _trackSort = TrackSort.title;

/// A music library by artists, albums, tracks, its folders on disk and playlists, each sorted as
/// the user picks and filtered by what is typed in the search field. It opens on the tab used last.
class MusicLibraryScreen extends StatefulWidget {
  const MusicLibraryScreen({super.key, required this.client, required this.library});

  final JellyfinClient client;
  final JellyfinItem library;

  @override
  State<MusicLibraryScreen> createState() => _MusicLibraryScreenState();
}

typedef _Music = ({
  List<JellyfinItem> tracks,
  List<ArtistGroup> artists,
  List<AlbumGroup> albums,
  MusicFolder folders,
});

const _tabNames = ['Artists', 'Albums', 'Tracks', 'Folders', 'Playlists'];
const _playlistsTab = 4;
const _tabKey = 'music.tab';

class _MusicLibraryScreenState extends State<MusicLibraryScreen> with JellyfinActions, SingleTickerProviderStateMixin {
  @override
  JellyfinClient get client => widget.client;

  late final TabController _tabs = TabController(length: _tabNames.length, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) {
        // Playlists may have changed from another tab's long press.
        if (_tabs.index == _playlistsTab) {
          _playlists = client.playlists();
          if (_contents != null) _contents = _loadContents();
        }
        // The tab the person chose, not one a search jumped to.
        if (!_searching) SharedPreferences.getInstance().then((p) => p.setInt(_tabKey, _tabs.index));
      }
      setState(() {});
    });

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final last = p.getInt(_tabKey);
      if (mounted && last != null && last >= 0 && last < _tabNames.length) _tabs.index = last;
    });
  }
  late Future<_Music> _music = _load();
  late Future<List<JellyfinItem>> _playlists = client.playlists();
  final _query = TextEditingController();
  bool _searching = false;

  /// The library once loaded, for the counts on the tabs while searching.
  _Music? _data;

  /// What is in each playlist, loaded when a search starts, so playlists holding a match show.
  Future<List<PlaylistContents>>? _contents;

  /// The same once it is there, for the count on the Playlists tab.
  List<PlaylistContents>? _contentsData;

  Future<_Music> _load() async {
    final tracks = await client.musicTracks(widget.library.id);
    final m = (
      tracks: tracks,
      artists: groupByArtist(tracks),
      albums: groupByAlbum(tracks),
      folders: buildMusicFolders(tracks),
    );
    if (mounted) setState(() => _data = m);
    return m;
  }

  Future<List<PlaylistContents>> _loadContents() async {
    final lists = await _playlists;
    final contents = await Future.wait([
      for (final p in lists)
        client.playlistItems(p.id).then((items) => (playlist: p, items: items)).onError((e, _) => (playlist: p, items: <JellyfinItem>[])),
    ]);
    if (mounted) {
      setState(() => _contentsData = contents);
      _goWhereFound();
    }
    return contents;
  }

  /// What the typed words find, over the library sorted as chosen.
  MusicHits _find(_Music m) => findInMusic(
    sortArtists(m.artists, _artistSort),
    sortAlbums(m.albums, _albumSort),
    sortTracks(m.tracks, _trackSort),
    _text,
  );

  void _typed() {
    _contents ??= _loadContents();
    setState(() {});
    _goWhereFound();
  }

  /// Nothing on this tab but something on another: go there, so a track name typed on the
  /// Artists or Playlists tab shows the track.
  void _goWhereFound() {
    final counts = _tabCounts;
    if (counts == null || _tabs.index >= counts.length || counts[_tabs.index] > 0) return;
    final first = counts.indexWhere((c) => c > 0);
    if (first >= 0) _tabs.animateTo(first);
  }

  @override
  void refresh() => setState(() {
    _music = _load();
    _playlists = client.playlists();
  });

  void _refreshPlaylists() => setState(() {
    _playlists = client.playlists();
    if (_contents != null) _contents = _loadContents();
  });

  /// Long press on a track or album may add to or make a playlist: the search should know.
  Future<void> _actions(List<JellyfinItem> items, JellyfinItem item) async {
    await itemActions(items, item);
    if (mounted && _contents != null) _refreshPlaylists();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  String get _text => _searching ? _query.text.trim() : '';

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
                onChanged: (_) => _typed(),
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
        ],
        bottom: TabBar(
          controller: _tabs,
          // With big letters the four names do not fit side by side: they scroll instead.
          isScrollable: MediaQuery.textScalerOf(context).scale(1) > 1.2,
          tabAlignment: MediaQuery.textScalerOf(context).scale(1) > 1.2 ? TabAlignment.start : null,
          tabs: [
            for (final (i, name) in _tabNames.indexed)
              Tab(text: switch (_tabCounts) {
                final counts? when i < counts.length => '$name · ${counts[i]}',
                _ => name,
              }),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _withMusic((m) => _artistList(m)),
          _withMusic((m) => _albumGrid(m)),
          _withMusic((m) => _trackList(m)),
          _withMusic((m) => _folders(m)),
          _playlistList(),
        ],
      ),
    );
  }

  /// How much each tab finds while searching; null when not searching.
  List<int>? get _tabCounts {
    final m = _data;
    if (m == null || _text.isEmpty) return null;
    final hits = _find(m);
    final lists = _contentsData;
    return [
      hits.artists.length,
      hits.albums.length,
      hits.tracks.length,
      findFolders(m.folders, _text).length,
      if (lists != null) findPlaylists(lists, _text).length,
    ];
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
    final artists = _find(m).artists;
    if (artists.isEmpty) return _Empty(query: q);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: artists.length,
      itemBuilder: (context, i) {
        final a = artists[i].group;
        final albums = a.albums.where((g) => !g.loose).length;
        return ListTile(
          leading: _RoundCover(client: client, item: a.cover),
          title: HighlightedText(a.name, query: q),
          subtitle: _has(artists[i].inside, q) ??
              Text(
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
          onLongPress: () => addToPlaylist(context, client, items: a.tracks).then((_) => _refreshPlaylists()),
        );
      },
    );
  }

  Widget _albumGrid(_Music m) {
    final q = _text;
    final hits = _find(m).albums;
    final albums = [for (final h in hits) h.group];
    if (albums.isEmpty) return _Empty(query: q);
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
            query: q,
            inside: hits[i].inside,
            onTap: () => _open(
              TrackListScreen(
                client: client,
                title: albums[i].name,
                subtitle: [albums[i].artist, albums[i].year?.toString()].whereType<String>().join(' · '),
                load: () async => albums[i].tracks,
                cover: albums[i].cover,
              ),
            ),
            onLongPress: () => addToPlaylist(context, client, items: albums[i].tracks).then((_) => _refreshPlaylists()),
          ),
        );
      },
    );
  }

  Widget _trackList(_Music m) {
    final q = _text;
    final tracks = _find(m).tracks;
    if (tracks.isEmpty) return _Empty(query: q);
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
          query: q,
          onTap: () => openItem(tracks, t),
          onLongPress: () => _actions(tracks, t),
        );
      },
    );
  }

  Widget _folders(_Music m) {
    final q = _text;
    if (q.isEmpty) return MusicFolderView(client: client, folder: m.folders);
    final hits = findFolders(m.folders, q);
    return hits.isEmpty ? _Empty(query: q) : MusicFolderHits(client: client, hits: hits, query: q);
  }

  Widget _playlistList() => PlaylistList(
    client: client,
    playlists: _playlists,
    onChanged: _refreshPlaylists,
    query: _text,
    contents: _text.isEmpty ? null : _contents,
  );

  /// "Has: Cluster One, Poles Apart" under an artist or album found by its tracks.
  Widget? _has(List<JellyfinItem> inside, String q) => inside.isEmpty
      ? null
      : HighlightedText(
          'Has: ${inside.take(3).map((t) => t.name).join(', ')}${inside.length > 3 ? ' and ${inside.length - 3} more' : ''}',
          query: q,
        );

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _refreshPlaylists();
  }
}

/// The user's playlists with a button for a new one; opening one shows its tracks.
class PlaylistList extends StatelessWidget {
  const PlaylistList({
    super.key,
    required this.client,
    required this.playlists,
    required this.onChanged,
    this.query = '',
    this.contents,
  });

  final JellyfinClient client;
  final Future<List<JellyfinItem>> playlists;

  /// Words being searched for: only playlists named so or holding a match show.
  final String query;

  /// What is in each playlist, for the search; null when not searching.
  final Future<List<PlaylistContents>>? contents;

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
  Widget build(BuildContext context) => FutureBuilder<(List<JellyfinItem>, List<PlaylistContents>?)>(
    future: playlists.then((l) async => (l, contents == null ? null : await contents)),
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return _Failed(error: snap.error!, onRetry: onChanged);
      final (all, inside) = snap.data!;
      final hits = inside == null || query.isEmpty
          ? [for (final p in all) Hit(p, const <JellyfinItem>[])]
          : findPlaylists(inside, query);
      final list = [for (final h in hits) h.group];
      final has = {for (final h in hits) h.group.id: h.inside};
      return RefreshIndicator(
        onRefresh: () async => onChanged(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (query.isEmpty)
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
                title: HighlightedText(p.name, query: query),
                subtitle: (has[p.id] ?? const []).isNotEmpty
                    ? HighlightedText(
                        'Has: ${has[p.id]!.take(3).map((t) => t.name).join(', ')}',
                        query: query,
                      )
                    : p.childCount == null
                    ? null
                    : Text(countLabelOf(p.childCount!, 'item')),
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
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  query.isNotEmpty
                      ? 'No playlist named so or holding "$query".'
                      : 'No playlists yet. Make one here, or long-press a track or an album and choose '
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
  const _AlbumCard({
    required this.client,
    required this.album,
    required this.onTap,
    required this.onLongPress,
    this.query = '',
    this.inside = const [],
  });

  final JellyfinClient client;
  final AlbumGroup album;
  final String query;

  /// Matching tracks, when the album is found by them.
  final List<JellyfinItem> inside;
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
            child: HighlightedText(album.name, query: query, style: theme.textTheme.bodyMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: HighlightedText(
              inside.isEmpty ? album.artist : 'Has: ${inside.map((t) => t.name).join(', ')}',
              query: query,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.query = ''});

  final String query;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            query.isEmpty ? 'Nothing here' : 'Nothing here for "$query". The other tabs may have it.',
            textAlign: TextAlign.center,
          ),
        ),
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
