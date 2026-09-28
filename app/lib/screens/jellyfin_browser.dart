import 'package:flutter/material.dart';

import '../api/jellyfin.dart';
import '../services/playback.dart';
import '../widgets/async_list.dart';
import 'player_screen.dart';

/// Libraries at the top level, then any folder: series, season, album...
class JellyfinBrowser extends StatelessWidget {
  const JellyfinBrowser({super.key, required this.client, required this.title, this.parentId});

  final JellyfinClient client;
  final String title;
  final String? parentId;

  IconData _icon(JellyfinItem item) => switch (item.type) {
        'CollectionFolder' || 'UserView' => Icons.folder,
        'MusicAlbum' || 'Audio' => Icons.album,
        'MusicArtist' => Icons.person,
        _ => item.isFolder ? Icons.folder : Icons.movie,
      };

  Future<void> _tap(BuildContext context, List<JellyfinItem> items, JellyfinItem item) async {
    final nav = Navigator.of(context);
    if (item.isFolder || !item.isPlayable) {
      nav.push(MaterialPageRoute(builder: (_) => JellyfinBrowser(client: client, title: item.name, parentId: item.id)));
      return;
    }
    // Episodes and tracks play through their season or album; a movie plays on its own.
    final playable = item.type == 'Episode' || item.type == 'Audio'
        ? items.where((i) => i.type == item.type).toList()
        : [item];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final queue = await Future.wait(playable.map((i) => client.resolve(i).onError((e, _) {
          debugPrint('homeplay PlaybackInfo failed for ${i.name}: $e');
          return client.toPlayItem(i);
        })));
    nav.pop();
    await Playback.instance.start(queue, playable.indexOf(item));
    nav.push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final id = parentId;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncList<JellyfinItem>(
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
            subtitle: item.subtitle == null || item.subtitle!.isEmpty ? null : Text(item.subtitle!),
            trailing: item.isPlayable ? const Icon(Icons.play_arrow) : null,
            onTap: () => _tap(context, items, item),
          );
        },
      ),
    );
  }
}
