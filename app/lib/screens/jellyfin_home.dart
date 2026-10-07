import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../services/appearance.dart';
import '../widgets/library_tiles.dart';
import '../widgets/media_cards.dart';
import 'backup_screen.dart';
import 'downloads_screen.dart';
import 'jellyfin_actions.dart';
import 'jellyfin_browser.dart';
import 'settings_screen.dart';

/// A Jellyfin server's front page: its libraries as big buttons, what is being watched, the next
/// episodes and the newest in each library, in rows of pictures.
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

  /// "124 movies" by library id, filled in after the page shows.
  final Map<String, String> _counts = {};

  @override
  void refresh() => setState(() => _home = _load());

  Future<_Home> _load() async {
    final libraries = await client.views();
    _countAll(libraries);
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

  Future<void> _countAll(List<JellyfinItem> libraries) async {
    await Future.wait([
      for (final l in libraries)
        _count(l).then((label) {
          if (label != null && mounted) setState(() => _counts[l.id] = label);
        }),
    ]);
  }

  Future<String?> _count(JellyfinItem library) async {
    var kind = libraryKind(library.collectionType);
    if (kind.types == null) return null;
    try {
      var n = await client.count(library.id, kind.types!);
      if (n == 0 && library.collectionType == 'music') {
        kind = tracksKind;
        n = await client.count(library.id, kind.types!);
      }
      return countLabel(n, kind);
    } catch (e) {
      debugPrint('homeplay library count failed: $e');
      return null;
    }
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _push(const SettingsScreen()),
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: () => _push(JellyfinBrowser(client: client, title: widget.title)),
                child: const ListTile(leading: Icon(Icons.folder_outlined), title: Text('Folders')),
              ),
              PopupMenuItem(
                value: () => _push(const DownloadsScreen()),
                child: const ListTile(leading: Icon(Icons.download_for_offline_outlined), title: Text('Downloads')),
              ),
              PopupMenuItem(
                value: () => _push(BackupScreen(account: client.account)),
                child: const ListTile(leading: Icon(Icons.backup_outlined), title: Text('Photo backup')),
              ),
              PopupMenuItem(
                value: () => Navigator.of(context).pop(),
                child: const ListTile(leading: Icon(Icons.dns_outlined), title: Text('All servers')),
              ),
            ],
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
              if (home.libraries.isNotEmpty) ...[
                ValueListenableBuilder<Appearance>(
                  valueListenable: AppearanceStore.current,
                  builder: (context, look, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SectionTitle('Libraries', trailing: LibraryLayoutButton(look: look)),
                    LibrariesView(
                      layout: look.libraries,
                      libraries: home.libraries,
                      counts: _counts,
                      onOpen: (l) => openItem(home.libraries, l),
                    ),
                  ]),
                ),
              ],
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
