import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';

/// Asks for a playlist name; null when cancelled.
Future<String?> askPlaylistName(BuildContext context, {String initial = '', String title = 'New playlist'}) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.pop(c, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(c, field.text.trim().isEmpty ? null : field.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(field.dispose);
}

/// Adds [items] to a playlist the user picks, or to a new one. [load] gives the items to add
/// when they are only known later (an album's tracks); it runs after the choice.
Future<void> addToPlaylist(
  BuildContext context,
  JellyfinClient client, {
  List<JellyfinItem> items = const [],
  Future<List<JellyfinItem>> Function()? load,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final playlists = client.playlists();
  // A playlist (id) or a new one ('' with a name).
  final picked = await showModalBottomSheet<(String id, String name)>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: FutureBuilder<List<JellyfinItem>>(
          future: playlists,
          builder: (context, snap) => ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Add to playlist', style: Theme.of(context).textTheme.titleMedium),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New playlist'),
                onTap: () async {
                  final name = await askPlaylistName(context);
                  if (name != null && context.mounted) Navigator.pop(context, ('', name));
                },
              ),
              if (snap.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snap.hasError)
                ListTile(title: Text(describeError(snap.error!)))
              else
                for (final p in snap.data!)
                  ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: p.childCount == null ? null : Text(countLabelOf(p.childCount!, 'item')),
                    onTap: () => Navigator.pop(context, (p.id, p.name)),
                  ),
            ],
          ),
        ),
      ),
    ),
  );
  if (picked == null) return;
  try {
    final all = [...items, if (load != null) ...await load()];
    final ids = [for (final i in all) i.id];
    if (ids.isEmpty) return;
    final (id, name) = picked;
    if (id.isEmpty) {
      await client.createPlaylist(name, ids, mediaType: all.every((i) => i.type == 'Audio') ? 'Audio' : 'Video');
    } else {
      await client.addToPlaylist(id, ids);
    }
    messenger.showSnackBar(SnackBar(content: Text('Added ${countLabelOf(ids.length, 'item')} to "$name"')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
  }
}

/// "1 item", "12 items".
String countLabelOf(int n, String word) => '$n ${n == 1 ? word : '${word}s'}';
