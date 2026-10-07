import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/jellyfin.dart';
import '../services/music_index.dart';
import '../services/search_filters.dart';
import '../services/search_index.dart';
import '../services/search_results.dart';
import '../widgets/async_list.dart';
import '../widgets/highlighted_text.dart';
import 'jellyfin_actions.dart';
import 'playlist_picker.dart';
import 'track_list_screen.dart';

const _recentKey = 'recent_searches';

/// Rows shown per section before "Show all".
const _sectionRows = 12;

/// Search across the whole server. As letters are typed, matches show at once from a list of
/// every file, album, folder and playlist kept on the phone, with the typed words marked; the
/// server's own search (shows, artists, collections, and the filters) joins in a moment later.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.client});

  final JellyfinClient client;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with JellyfinActions {
  @override
  JellyfinClient get client => widget.client;

  final _field = TextEditingController();
  final _focus = FocusNode();
  SearchFilters _filters = const SearchFilters();

  /// The phone's own list to search in; null while it loads.
  SearchIndex? _index;
  Object? _indexError;

  /// The server's answer for the current words and filters.
  List<JellyfinItem> _server = const [];
  bool _asking = false;
  int _asked = 0;

  Timer? _typing;
  List<String> _recent = const [];
  Future<List<String>>? _genres;

  /// Sections opened to show all their rows.
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _recent = p.getStringList(_recentKey) ?? const []);
    });
    _buildIndex();
  }

  Future<void> _buildIndex() async {
    try {
      final files = client.allFiles();
      final lists = await client.playlists();
      final contents = await Future.wait([
        for (final p in lists)
          client.playlistItems(p.id).then((items) => (playlist: p, items: items)).onError((e, _) => (playlist: p, items: <JellyfinItem>[])),
      ]);
      final index = SearchIndex(await files, contents);
      if (mounted) setState(() => _index = index);
    } catch (e) {
      debugPrint('homeplay search index failed: $e');
      if (mounted) setState(() => _indexError = e);
    }
  }

  @override
  void dispose() {
    _typing?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void refresh() => _askServer();

  void _set(SearchFilters f, {bool now = true}) {
    _filters = f;
    _expanded.clear();
    _typing?.cancel();
    // The phone's list answers at once with this rebuild; the server once typing pauses.
    if (now) {
      _askServer();
    } else {
      setState(() {});
      _typing = Timer(const Duration(milliseconds: 350), _askServer);
    }
  }

  Future<void> _askServer() async {
    final f = _filters;
    final ask = ++_asked;
    if (!f.isReady || f.kind.types == null && !f.wantsArtists) {
      setState(() {
        _server = const [];
        _asking = false;
      });
      return;
    }
    setState(() => _asking = true);
    try {
      final found = await client.search(f);
      if (mounted && ask == _asked) setState(() => _server = found);
    } catch (e) {
      debugPrint('homeplay search failed: $e');
    } finally {
      if (mounted && ask == _asked) setState(() => _asking = false);
    }
  }

  Future<void> _remember() async {
    final text = _filters.text.trim();
    if (text.isEmpty) return;
    final recent = rememberSearch(_recent, text);
    setState(() => _recent = recent);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_recentKey, recent);
  }

  Future<void> _open(List<JellyfinItem> section, JellyfinItem item) async {
    unawaited(_remember());
    switch (item.type) {
      case 'Movie' || 'Series':
        await openItem([item], item, details: true);
      case 'Audio' || 'Photo':
        await openItem(section, item);
      default:
        if (item.isPlayable) {
          await openItem([item], item);
        } else {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => jellyfinPage(client, item)));
        }
    }
  }

  void _openList(String title, String? subtitle, List<JellyfinItem> items, {JellyfinItem? cover}) {
    unawaited(_remember());
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackListScreen(client: client, title: title, subtitle: subtitle, load: () async => items, cover: cover),
    ));
  }

  void _openPlaylist(JellyfinItem playlist) {
    unawaited(_remember());
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrackListScreen.playlist(client: client, playlist: playlist)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loading = _asking || (_index == null && _indexError == null && _filters.isReady);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _field,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Search the server', border: InputBorder.none),
          onChanged: (t) => _set(_filters.copyWith(text: t), now: false),
          onSubmitted: (t) {
            _set(_filters.copyWith(text: t));
            _remember();
          },
        ),
        actions: [
          if (_field.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () {
                _field.clear();
                _set(_filters.copyWith(text: ''));
              },
            ),
          IconButton(
            tooltip: 'Filters',
            icon: Badge(
              isLabelVisible: _filters.extraFilters > 0,
              label: Text('${_filters.extraFilters}'),
              child: const Icon(Icons.tune),
            ),
            onPressed: _showFilters,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Column(children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  for (final k in SearchKind.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(k.label),
                        selected: _filters.kind == k,
                        onSelected: (_) => _set(_filters.copyWith(kind: k)),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 4, child: loading ? const LinearProgressIndicator() : null),
          ]),
        ),
      ),
      body: _filters.isReady ? _results(theme) : _idle(theme),
    );
  }

  /// Before a search: the last ones, and what can be looked for.
  Widget _idle(ThemeData theme) => ListView(
    children: [
      if (_recent.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text('Recent', style: theme.textTheme.titleSmall)),
              TextButton(
                onPressed: () async {
                  setState(() => _recent = const []);
                  (await SharedPreferences.getInstance()).remove(_recentKey);
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        for (final r in _recent)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(r),
            onTap: () {
              _field.text = r;
              _set(_filters.copyWith(text: r));
            },
          ),
      ],
      Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Type part of a name: tracks, albums, folders, playlists, movies and photos show as you type. '
          'Or pick a kind and filters: for example Movies, 1990 to 1999, not watched.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    ],
  );

  Widget _results(ThemeData theme) {
    final f = _filters;
    final query = f.text;
    // The phone's list answers words; filters by year, genre or watched are the server's.
    final local = _index != null && f.extraFilters == 0
        ? _index!.find(query, f.kind)
        : _index != null && f.kind == SearchKind.albums
            ? LocalHits(albums: [
                for (final a in findAlbums(_index!.albums, query, from: f.fromYear, to: f.toYear)) Hit(a, const []),
              ])
            : const LocalHits();
    final seen = <String>{};
    final items = [...local.items, ..._server].where((i) => seen.add(i.id)).toList();
    final playlistIds = {for (final h in local.playlists) h.group.id};
    final sections = groupResults(items.where((i) => !(i.type == 'Playlist' && playlistIds.contains(i.id))).toList());
    final bySection = {for (final (title, list) in sections) title: list};

    final rows = <Widget>[];
    void section<T>(String title, List<T> list, Widget Function(T) row) {
      if (list.isEmpty) return;
      final open = _expanded.contains(title) || list.length <= _sectionRows + 2;
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text('$title · ${list.length}',
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
          if (!open) TextButton(onPressed: () => setState(() => _expanded.add(title)), child: const Text('Show all')),
        ]),
      ));
      rows.addAll(list.take(open ? list.length : _sectionRows).map(row));
    }

    Widget itemRow(List<JellyfinItem> list, JellyfinItem item) {
      // Found by the file name and not the title: the file name shows why.
      final sub = foundByFileName(item, query) ? 'File: ${item.fileName}' : resultSubtitle(item);
      return ListTile(
        leading: ArtThumb(
          url: item.isPhoto ? client.photoUrl(item, maxSide: 200) : client.imageUrl(item, height: 168),
          headers: client.headers,
          icon: itemIcon(item),
          aspect: item.imageAspect,
        ),
        title: HighlightedText(item.name, query: query, maxLines: 2),
        subtitle: sub.isEmpty ? null : HighlightedText(sub, query: query, style: theme.textTheme.bodySmall),
        onTap: () => _open(list, item),
        onLongPress: item.isPlayable || item.type == 'MusicAlbum' ? () => itemActions(list, item) : null,
      );
    }

    Widget? inside(List<JellyfinItem> found) => found.isEmpty
        ? null
        : HighlightedText('Has: ${found.take(3).map((i) => i.name).join(', ')}${found.length > 3 ? ' and ${found.length - 3} more' : ''}',
            query: query, style: theme.textTheme.bodySmall);

    for (final title in const ['Movies', 'Shows', 'Episodes', 'Artists']) {
      final list = bySection[title] ?? const [];
      section(title, list, (JellyfinItem i) => itemRow(list, i));
    }
    section('Albums', local.albums, (Hit<AlbumGroup> h) {
      final a = h.group;
      return ListTile(
        leading: ArtThumb(url: client.imageUrl(a.cover, height: 168), headers: client.headers, icon: Icons.album),
        title: HighlightedText(a.name, query: query, maxLines: 2),
        subtitle: inside(h.inside) ??
            HighlightedText(
              [a.artist, a.year?.toString(), '${a.tracks.length} ${a.tracks.length == 1 ? 'track' : 'tracks'}']
                  .whereType<String>()
                  .join(' · '),
              query: query,
              style: theme.textTheme.bodySmall,
            ),
        onTap: () => _openList(a.name, [a.artist, a.year?.toString()].whereType<String>().join(' · '), a.tracks, cover: a.cover),
        onLongPress: () => addToPlaylist(context, client, items: a.tracks),
      );
    });
    final tracks = bySection['Tracks'] ?? const [];
    section('Tracks', tracks, (JellyfinItem i) => itemRow(tracks, i));
    section('Folders', local.folders, (Hit<FolderGroup> h) {
      final folder = h.group;
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(Icons.folder_rounded, color: theme.colorScheme.onSecondaryContainer),
        ),
        title: HighlightedText(folder.name, query: query),
        subtitle: inside(h.inside) ?? Text(folder.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        onTap: () => _openList(folder.name, folder.path, folder.items),
      );
    });
    final serverPlaylists = bySection['Playlists'] ?? const [];
    section('Playlists', [...local.playlists, for (final p in serverPlaylists) Hit(p, const <JellyfinItem>[])],
        (Hit<JellyfinItem> h) {
      final p = h.group;
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.tertiaryContainer,
          child: Icon(Icons.queue_music_rounded, color: theme.colorScheme.onTertiaryContainer),
        ),
        title: HighlightedText(p.name, query: query),
        subtitle: inside(h.inside) ?? (p.childCount == null ? null : Text(countLabelOf(p.childCount!, 'item'))),
        onTap: () => _openPlaylist(p),
      );
    });
    for (final title in const ['Videos', 'Collections', 'Photos', 'Other']) {
      final list = bySection[title] ?? const [];
      section(title, list, (JellyfinItem i) => itemRow(list, i));
    }

    if (rows.isEmpty) {
      final waiting = _asking || (_index == null && _indexError == null);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            waiting
                ? 'Looking…'
                : f.kind == SearchKind.artists && query.trim().isEmpty
                    ? 'Type an artist\'s name'
                    : 'Nothing found. Try fewer letters or filters.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: rows);
  }

  Future<void> _showFilters() async {
    _genres ??= client.genres().onError((e, _) => const <String>[]);
    // Without this the keyboard came back over the results when the sheet closed.
    _focus.unfocus();
    final result = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FiltersSheet(initial: _filters, genres: _genres!),
    );
    if (result != null) _set(result);
    // Closing the sheet gives the focus back to the field it was taken from: take it again.
    if (mounted) _focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.unfocus();
    });
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initial, required this.genres});

  final SearchFilters initial;
  final Future<List<String>> genres;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late SearchFilters _f = widget.initial;
  late final _from = TextEditingController(text: widget.initial.fromYear?.toString() ?? '');
  late final _to = TextEditingController(text: widget.initial.toYear?.toString() ?? '');

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  int? _year(String s) {
    final y = int.tryParse(s.trim());
    return y != null && y >= 1800 && y <= 2200 ? y : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filters', style: theme.textTheme.titleMedium),
                heading('Year'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _from,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'From',
                          hintText: '1990',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _f = _f.copyWith(fromYear: () => _year(v))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _to,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'To',
                          hintText: '1999',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _f = _f.copyWith(toYear: () => _year(v))),
                      ),
                    ),
                  ],
                ),
                heading('Watched'),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<Watched>(
                    showSelectedIcon: false,
                    segments: [
                      for (final w in Watched.values)
                        ButtonSegment(
                          value: w,
                          label: Text(w.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    selected: {_f.watched},
                    onSelectionChanged: (s) => setState(() => _f = _f.copyWith(watched: s.first)),
                  ),
                ),
                heading('Order'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in SearchSort.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: _f.sort == s,
                        onSelected: (_) => setState(() => _f = _f.copyWith(sort: s)),
                      ),
                  ],
                ),
                heading('Genres'),
                FutureBuilder<List<String>>(
                  future: widget.genres,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                    final all = snap.data ?? const [];
                    if (all.isEmpty) return const Text('The server has no genres.');
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final g in all)
                          FilterChip(
                            label: Text(g),
                            selected: _f.genres.contains(g),
                            onSelected: (on) => setState(
                              () => _f = _f.copyWith(genres: on ? {..._f.genres, g} : ({..._f.genres}..remove(g))),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, SearchFilters(text: _f.text, kind: _f.kind)),
                      child: const Text('Reset'),
                    ),
                    const Spacer(),
                    FilledButton(onPressed: () => Navigator.pop(context, _f), child: const Text('Show results')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
