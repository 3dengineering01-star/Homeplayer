import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../widgets/media_cards.dart';
import 'jellyfin_actions.dart';
import 'jellyfin_browser.dart';

/// A movie, show or music library as a grid of posters, loaded page by page as it scrolls.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.client, required this.library, required this.types});

  final JellyfinClient client;
  final JellyfinItem library;

  /// Jellyfin item types to show: 'Movie', 'Series', 'MusicAlbum'...
  final String types;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

/// The order picked for each library while the app runs.
final Map<String, LibrarySort> _sortByLibrary = {};

class _LibraryScreenState extends State<LibraryScreen> with JellyfinActions {
  @override
  JellyfinClient get client => widget.client;

  late LibrarySort _sort = _sortByLibrary[widget.library.id] ?? LibrarySort.name;
  final List<JellyfinItem> _items = [];
  int _total = -1;
  bool _loading = false;
  Object? _error;
  final _scroll = ScrollController();

  bool get _square => widget.types == 'MusicAlbum';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) _more();
    });
    _more();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    if (_loading || (_total >= 0 && _items.length >= _total)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await client.libraryPage(widget.library.id, types: widget.types, sort: _sort, start: _items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.items.isEmpty ? _items.length : page.total;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _total = -1;
    });
    await _more();
  }

  @override
  void refresh() => _reload();

  @override
  Widget build(BuildContext context) {
    // Music without album tags has no albums: the tracks lie in the library itself.
    if (_square && _total == 0 && !_loading && _error == null) {
      return JellyfinBrowser(client: client, title: widget.library.name, parentId: widget.library.id);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.library.name),
        actions: [
          PopupMenuButton<LibrarySort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) {
              _sortByLibrary[widget.library.id] = s;
              setState(() => _sort = s);
              _reload();
            },
            itemBuilder: (_) => [for (final s in LibrarySort.values) PopupMenuItem(value: s, child: Text(s.label))],
          ),
          IconButton(
            tooltip: 'Folders',
            icon: const Icon(Icons.folder_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => JellyfinBrowser(client: client, title: widget.library.name, parentId: widget.library.id))),
          ),
        ],
      ),
      body: _items.isEmpty && _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(describeError(_error!), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                ]),
              ),
            )
          : _items.isEmpty && !_loading
              ? const Center(child: Text('Nothing here'))
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: _square ? 170 : 140,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      // Picture plus two lines of text under it.
                      childAspectRatio: _square ? 0.74 : 0.5,
                    ),
                    itemCount: _items.length + (_loading ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= _items.length) return const Center(child: CircularProgressIndicator());
                      final item = _items[i];
                      return LayoutBuilder(
                        builder: (context, box) => PosterCard(
                          item: item,
                          client: client,
                          width: box.maxWidth,
                          square: _square,
                          onTap: () => openItem(_items, item, details: true),
                          onLongPress: () => itemActions(_items, item),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
