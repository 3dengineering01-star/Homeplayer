import 'package:flutter/material.dart';

import '../api/jellyfin.dart';
import '../services/licence.dart';
import '../services/appearance.dart';
import '../services/library_order.dart';
import '../widgets/library_tiles.dart';
import '../widgets/media_cards.dart';
import 'backup_screen.dart';
import 'downloads_screen.dart';
import 'jellyfin_actions.dart';
import 'jellyfin_browser.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'pro_screen.dart';
import 'share_screen.dart';
import '../widgets/error_view.dart';

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

  /// The order and hidden libraries the person chose for this server.
  LibraryOrder _order = const LibraryOrder();

  @override
  void initState() {
    super.initState();
    LibraryOrder.load(client.account.id).then((o) {
      if (mounted) setState(() => _order = o);
    });
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

  Future<void> _arrange(List<JellyfinItem> libraries) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ArrangeSheet(
        libraries: libraries,
        order: _order,
        onChanged: (o) {
          setState(() => _order = o);
          o.save(client.account.id);
        },
      ),
    );
  }

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
                value: () => _libraries.then(_arrange, onError: (_) {}),
                child: const ListTile(leading: Icon(Icons.reorder), title: Text('Arrange libraries')),
              ),
              PopupMenuItem(
                value: () => _push(const DownloadsScreen()),
                child: const ListTile(leading: Icon(Icons.download_for_offline_outlined), title: Text('Downloads')),
              ),
              if (_owner)
                PopupMenuItem(
                  value: () => withPro(context, ProFeature.share, () => _push(ShareScreen(client: client)),
                      account: client.account),
                  child: const ListTile(leading: Icon(Icons.group_add_outlined), title: Text('Share with friends')),
                ),
              PopupMenuItem(
                value: () => withPro(context, ProFeature.backup, () => _push(BackupScreen(account: client.account)),
                    account: client.account),
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
            return ErrorView(error: snap.error!, onRetry: refresh);
          }
          final all = snap.data!;
          final libraries = _order.arrange(all, (l) => l.id);
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
              if (all.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No libraries on this server'))),
              if (all.isNotEmpty && libraries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(children: [
                    const Text('All libraries are hidden'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(onPressed: () => _arrange(all), child: const Text('Arrange libraries')),
                  ]),
                ),
            ]),
          );
        },
      ),
    );
  }
}

/// The server's libraries to drag into another order and to show or hide.
class _ArrangeSheet extends StatefulWidget {
  const _ArrangeSheet({required this.libraries, required this.order, required this.onChanged});

  final List<JellyfinItem> libraries;
  final LibraryOrder order;
  final void Function(LibraryOrder) onChanged;

  @override
  State<_ArrangeSheet> createState() => _ArrangeSheetState();
}

class _ArrangeSheetState extends State<_ArrangeSheet> {
  late LibraryOrder _order = widget.order;
  late List<JellyfinItem> _all = _order.arrange(widget.libraries, (l) => l.id, withHidden: true);

  void _set(LibraryOrder o) {
    setState(() => _order = o);
    widget.onChanged(o);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height * 0.8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
          child: Row(children: [
            Expanded(child: Text('Arrange libraries', style: Theme.of(context).textTheme.titleLarge)),
            if (!_order.isDefault)
              TextButton(
                onPressed: () {
                  _all = const LibraryOrder().arrange(widget.libraries, (l) => l.id, withHidden: true);
                  _set(const LibraryOrder());
                },
                child: const Text('Reset'),
              ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Drag to change the order. Untick a library to hide it on this phone; nothing changes on the server.'),
        ),
        Flexible(
          child: ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            itemCount: _all.length,
            onReorderItem: (from, to) {
              final moved = _all.removeAt(from);
              _all.insert(to, moved);
              _set(_order.copyWith(order: [for (final l in _all) l.id]));
            },
            itemBuilder: (context, i) {
              final l = _all[i];
              final shown = !_order.hidden.contains(l.id);
              return CheckboxListTile(
                key: ValueKey(l.id),
                value: shown,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l.name, style: shown ? null : TextStyle(color: Theme.of(context).disabledColor)),
                secondary: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                onChanged: (on) => _set(_order.copyWith(
                  hidden: on == true ? ({..._order.hidden}..remove(l.id)) : {..._order.hidden, l.id},
                )),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}
