import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/subsonic.dart';
import '../services/playback.dart';
import '../widgets/async_list.dart';
import '../widgets/media_cards.dart';
import '../widgets/queue_sheet.dart';
import 'player_screen.dart';
import '../widgets/error_view.dart';

/// A Subsonic server's music: Home with what is new and what is played, then the artists.
class SubsonicArtists extends StatelessWidget {
  const SubsonicArtists({super.key, required this.client, required this.title});
  final SubsonicClient client;
  final String title;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(tabs: [Tab(text: 'Home'), Tab(text: 'Artists')]),
        ),
        body: TabBarView(children: [
          SubsonicHome(client: client),
          _artists(context),
        ]),
      ),
    );
  }

  Widget _artists(BuildContext context) => AsyncList<SubsonicEntry>(
        load: client.artists,
        emptyText: 'No artists yet. Has the server finished scanning?',
        itemBuilder: (context, items, i) {
          final a = items[i];
          return ListTile(
            leading: ArtThumb(url: client.coverUrl(a.coverArt, size: 168), icon: Icons.person),
            title: Text(a.title),
            subtitle: a.subtitle == null ? null : Text(a.subtitle!),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SubsonicAlbums(client: client, artist: a)),
            ),
          );
        },
      );
}

/// What the server lists: albums added and played last, played most and marked as favorites,
/// favorite songs, and a shuffle of the whole library.
class SubsonicHome extends StatefulWidget {
  const SubsonicHome({super.key, required this.client});
  final SubsonicClient client;

  @override
  State<SubsonicHome> createState() => _SubsonicHomeState();
}

typedef _Shelves = ({
  List<SubsonicEntry> newest,
  List<SubsonicEntry> recent,
  List<SubsonicEntry> frequent,
  List<SubsonicEntry> starred,
  List<SubsonicEntry> songs,
});

class _SubsonicHomeState extends State<SubsonicHome> {
  late Future<_Shelves> _shelves = _load();

  Future<_Shelves> _load() async {
    final c = widget.client;
    // One list the server cannot give (an old server) leaves its shelf out, not the page.
    Future<List<SubsonicEntry>> safe(Future<List<SubsonicEntry>> f) => f.catchError((Object e) {
          debugPrint('homeplay subsonic home list failed: $e');
          return <SubsonicEntry>[];
        });
    final lists = await Future.wait([
      c.albumList('newest'),
      safe(c.albumList('recent')),
      safe(c.albumList('frequent')),
      safe(c.albumList('starred')),
      safe(c.starredSongs()),
    ]);
    return (newest: lists[0], recent: lists[1], frequent: lists[2], starred: lists[3], songs: lists[4]);
  }

  Future<void> _play(List<SubsonicEntry> songs, int index) async {
    final nav = Navigator.of(context);
    await Playback.instance.start(songs.map(widget.client.toPlayItem).toList(), index);
    nav.push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  Future<void> _shuffleAll() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final songs = await widget.client.randomSongs();
      if (songs.isNotEmpty && mounted) await _play(songs, 0);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Shelves>(
        future: _shelves,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return ErrorView(error: snap.error!, onRetry: () => setState(() => _shelves = _load()));
          }
          final s = snap.data!;
          final theme = Theme.of(context);
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _shelves = _load());
              await _shelves.then((_) {}, onError: (_) {});
            },
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: FilledButton.tonalIcon(
                  onPressed: _shuffleAll,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle all'),
                ),
              ),
              if (s.newest.isNotEmpty) _albums('Recently added', s.newest),
              if (s.recent.isNotEmpty) _albums('Recently played', s.recent),
              if (s.frequent.isNotEmpty) _albums('Most played', s.frequent),
              if (s.starred.isNotEmpty) _albums('Favorite albums', s.starred),
              if (s.songs.isNotEmpty) ...[
                const SectionTitle('Favorite songs'),
                for (final (i, song) in s.songs.take(10).indexed)
                  ListTile(
                    leading: ArtThumb(url: widget.client.coverUrl(song.coverArt, size: 168), icon: Icons.music_note),
                    title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: song.subtitle == null ? null : Text(song.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _play(s.songs, i),
                    onLongPress: () => showQueueMenu(context, song.title, [widget.client.toPlayItem(song)]),
                  ),
              ],
              if (s.recent.isEmpty && s.frequent.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Play some music: what you listen to most shows up here.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
            ]),
          );
        },
      );

  Widget _albums(String title, List<SubsonicEntry> albums) {
    const width = 140.0;
    final theme = Theme.of(context);
    return Shelf(
      title: title,
      height: width + 8 + MediaQuery.textScalerOf(context).scale(40),
      children: [
        for (final a in albums)
          SizedBox(
            width: width,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SubsonicSongs(client: widget.client, album: a)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox.square(
                    dimension: width,
                    child: NetImage(url: widget.client.coverUrl(a.coverArt, size: 360), headers: const {}, icon: Icons.album),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
                  child: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                ),
                if (a.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(a.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
              ]),
            ),
          ),
      ],
    );
  }
}

class SubsonicAlbums extends StatelessWidget {
  const SubsonicAlbums({super.key, required this.client, required this.artist});
  final SubsonicClient client;
  final SubsonicEntry artist;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(artist.title)),
      body: AsyncList<SubsonicEntry>(
        load: () => client.albums(artist.id),
        itemBuilder: (context, items, i) {
          final a = items[i];
          return ListTile(
            leading: ArtThumb(url: client.coverUrl(a.coverArt, size: 168), icon: Icons.album),
            title: Text(a.title),
            subtitle: a.subtitle == null ? null : Text(a.subtitle!),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SubsonicSongs(client: client, album: a)),
            ),
          );
        },
      ),
    );
  }
}

class SubsonicSongs extends StatelessWidget {
  const SubsonicSongs({super.key, required this.client, required this.album});
  final SubsonicClient client;
  final SubsonicEntry album;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(album.title), actions: [
        IconButton(
          tooltip: 'Play next or add to the queue',
          icon: const Icon(Icons.playlist_add),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final List<SubsonicEntry> songs;
            try {
              songs = await client.songs(album.id);
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
              return;
            }
            if (context.mounted) await showQueueMenu(context, album.title, songs.map(client.toPlayItem).toList());
          },
        ),
      ]),
      body: AsyncList<SubsonicEntry>(
        load: () => client.songs(album.id),
        itemBuilder: (context, items, i) {
          final s = items[i];
          return ListTile(
            leading: SizedBox(width: 32, child: Center(child: Text('${i + 1}'))),
            title: Text(s.title),
            subtitle: s.subtitle == null ? null : Text(s.subtitle!),
            onTap: () async {
              final nav = Navigator.of(context);
              await Playback.instance.start(items.map(client.toPlayItem).toList(), i);
              nav.push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
            },
            onLongPress: () => showQueueMenu(context, s.title, [client.toPlayItem(s)]),
          );
        },
      ),
    );
  }
}
