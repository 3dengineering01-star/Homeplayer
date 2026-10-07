import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../widgets/media_cards.dart';
import 'jellyfin_actions.dart';
import 'jellyfin_browser.dart';
import 'settings_screen.dart';

/// A Jellyfin server's front page: its libraries, what is being watched, the next episodes and
/// the newest in each library, in rows of pictures.
class JellyfinHome extends StatefulWidget {
  const JellyfinHome({super.key, required this.client, required this.title});

  final JellyfinClient client;
  final String title;

  @override
  State<JellyfinHome> createState() => _JellyfinHomeState();
}

typedef _Home = ({
  List<JellyfinItem> libraries,
  List<JellyfinItem> resume,
  List<JellyfinItem> nextUp,
  List<(JellyfinItem, List<JellyfinItem>)> latest,
});

class _JellyfinHomeState extends State<JellyfinHome> with JellyfinActions {
  @override
  JellyfinClient get client => widget.client;

  late Future<_Home> _home = _load();

  @override
  void refresh() => setState(() => _home = _load());

  Future<_Home> _load() async {
    final libraries = await client.views();
    // Each row on its own: one failing (an old server without an endpoint) leaves the rest.
    Future<List<JellyfinItem>> safe(Future<List<JellyfinItem>> f) => f.onError((e, _) {
          debugPrint('homeplay home row failed: $e');
          return const [];
        });
    final withLatest = libraries.where((l) => posterTypes(l.collectionType) != null).toList();
    final results = await Future.wait([
      safe(client.resume()),
      safe(client.nextUp()),
      for (final l in withLatest) safe(client.latest(l.id)),
    ]);
    return (
      libraries: libraries,
      resume: results[0],
      nextUp: results[1].where((n) => !results[0].any((r) => r.id == n.id)).toList(),
      latest: [
        for (final (i, l) in withLatest.indexed)
          if (results[i + 2].isNotEmpty) (l, results[i + 2]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          IconButton(
            tooltip: 'Folders',
            icon: const Icon(Icons.folder_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => JellyfinBrowser(client: client, title: widget.title))),
          ),
        ],
      ),
      body: FutureBuilder<_Home>(
        future: _home,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(describeError(snap.error!), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: refresh, child: const Text('Retry')),
                ]),
              ),
            );
          }
          final home = snap.data!;
          return RefreshIndicator(
            onRefresh: () async {
              refresh();
              await _home.then((_) {}, onError: (_) {});
            },
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              if (home.libraries.isNotEmpty)
                Shelf(
                  title: 'Libraries',
                  height: 130,
                  children: [
                    for (final l in home.libraries)
                      WideCard(
                        item: l,
                        client: client,
                        width: 180,
                        image: client.imageUrl(l, height: 240),
                        // Jellyfin's library pictures carry the name already.
                        title: l.hasPrimaryImage ? '' : l.name,
                        subtitle: '',
                        onTap: () => openItem(home.libraries, l),
                      ),
                  ],
                ),
              if (home.resume.isNotEmpty)
                Shelf(
                  title: 'Continue watching',
                  height: 190,
                  children: [
                    for (final r in home.resume)
                      WideCard(
                        item: r,
                        client: client,
                        onTap: () => openItem([r], r),
                        onLongPress: () => itemActions([r], r),
                      ),
                  ],
                ),
              if (home.nextUp.isNotEmpty)
                Shelf(
                  title: 'Next up',
                  height: 190,
                  children: [
                    for (final n in home.nextUp)
                      WideCard(
                        item: n,
                        client: client,
                        onTap: () => openItem([n], n),
                        onLongPress: () => itemActions([n], n),
                      ),
                  ],
                ),
              for (final (library, items) in home.latest)
                Shelf(
                  title: 'New in ${library.name}',
                  height: library.collectionType == 'music' ? 196 : 236,
                  onMore: () => openItem(home.libraries, library),
                  children: [
                    for (final item in items)
                      PosterCard(
                        item: item,
                        client: client,
                        square: library.collectionType == 'music',
                        width: library.collectionType == 'music' ? 140 : 120,
                        onTap: () => openItem(items, item, details: true),
                        onLongPress: () => itemActions(items, item),
                      ),
                  ],
                ),
              if (home.libraries.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No libraries on this server'))),
            ]),
          );
        },
      ),
    );
  }
}
