import 'package:flutter/material.dart';

import '../api/subsonic.dart';
import '../services/playback.dart';
import '../widgets/async_list.dart';
import 'player_screen.dart';

class SubsonicArtists extends StatelessWidget {
  const SubsonicArtists({super.key, required this.client, required this.title});
  final SubsonicClient client;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncList<SubsonicEntry>(
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
      ),
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
      appBar: AppBar(title: Text(album.title)),
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
          );
        },
      ),
    );
  }
}
