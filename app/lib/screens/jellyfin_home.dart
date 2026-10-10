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
import 'search_screen.dart';
import 'settings_screen.dart';
import 'share_screen.dart';

/// A Jellyfin server's front page: its libraries. What is being watched is inside the movie and
/// show libraries.
class JellyfinHome extends StatefulWidget {
  const JellyfinHome({super.key, required this.client, required this.title});

  final JellyfinClient client;
  final String title;

  @override
  State<JellyfinHome> createState() => _JellyfinHomeState();
}

class _JellyfinHomeState extends State<JellyfinHome> with JellyfinActions {
  @override
  JellyfinClient get client => widget.client;

  late Future<List<JellyfinItem>> _libraries = _load();

  /// "124 movies" by library id, filled in after the page shows.
  final Map<String, String> _counts = {};

  /// Whether this sign-in owns the server: only the owner shares it. A friend never sees the
  /// menu item, and the server refuses them anyway.
  bool _owner = false;

  @override
  void initState() {
    super.initState();
    client.isAdmin().then((admin) {
      if (mounted) setState(() => _owner = admin);
    }, onError: (Object e) => debugPrint('homeplay owner check failed: $e'));
  }

  @override
  void refresh() => setState(() => _libraries = _load());

  Future<List<JellyfinItem>> _load() async {
    final libraries = await client.views();
    _countAll(libraries);
    return libraries;
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
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => _push(SearchScreen(client: client)),
          ),
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
              if (_owner)
                PopupMenuItem(
                  value: () => _push(ShareScreen(client: client)),
                  child: const ListTile(leading: Icon(Icons.group_add_outlined), title: Text('Share with friends')),
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
      body: FutureBuilder<List<JellyfinItem>>(
        future: _libraries,
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
          final libraries = snap.data!;
          return RefreshIndicator(
            onRefresh: () async {
              refresh();
              await _libraries.then((_) {}, onError: (_) {});
            },
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              if (libraries.isNotEmpty)
                ValueListenableBuilder<Appearance>(
                  valueListenable: AppearanceStore.current,
                  builder: (context, look, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SectionTitle('Libraries', trailing: LibraryLayoutButton(look: look)),
                    LibrariesView(
                      layout: look.libraries,
                      libraries: libraries,
                      counts: _counts,
                      onOpen: (l) => openItem(libraries, l),
                    ),
                  ]),
                ),
              if (libraries.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No libraries on this server'))),
            ]),
          );
        },
      ),
    );
  }
}
