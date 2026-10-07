import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../services/music_index.dart';
import '../services/search_filters.dart';
import '../services/search_results.dart';
import '../widgets/async_list.dart';
import 'jellyfin_actions.dart';
import 'playlist_picker.dart';
import 'track_list_screen.dart';

const _recentKey = 'recent_searches';

typedef _Found = ({List<JellyfinItem> items, List<AlbumGroup> albums});

/// Search across the whole server: words, a kind of item, years, genres, watched or not, and
/// the order. Results come in sections by kind.
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

  /// The server's albums as the music screen makes them, loaded once when first needed.
  Future<List<AlbumGroup>>? _albums;
  SearchFilters _filters = const SearchFilters();
  Future<_Found>? _results;
  Timer? _typing;
  List<String> _recent = const [];
  Future<List<String>>? _genres;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _recent = p.getStringList(_recentKey) ?? const []);
    });
  }

  @override
  void dispose() {
    _typing?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void refresh() => _run();

  void _set(SearchFilters f, {bool now = true}) {
    _filters = f;
    _typing?.cancel();
    if (now) {
      _run();
    } else {
      // Asked once typing pauses, not on every letter.
      _typing = Timer(const Duration(milliseconds: 400), _run);
      setState(() {});
    }
  }

  void _run() => setState(() => _results = _filters.isReady ? _search(_filters) : null);

  Future<_Found> _search(SearchFilters f) async {
    final albums = f.wantsAlbums ? (_albums ??= client.allMusicTracks().then(groupByAlbum)) : null;
    final items = client.search(f);
    return (
      items: await items,
      albums: albums == null ? const <AlbumGroup>[] : findAlbums(await albums, f.text, from: f.fromYear, to: f.toYear),
    );
  }

  void _openAlbum(AlbumGroup a) {
    unawaited(_remember());
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackListScreen(
        client: client,
        title: a.name,
        subtitle: [a.artist, a.year?.toString()].whereType<String>().join(' · '),
        load: () async => a.tracks,
        cover: a.cover,
      ),
    ));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
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
        ),
      ),
      body: _results == null ? _idle(theme) : _resultList(),
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
          'Type a name, or pick a kind and filters: for example Movies, 1990 to 1999, not watched.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    ],
  );

  Widget _resultList() => FutureBuilder<_Found>(
    future: _results,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) {
        return Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text(describeError(snap.error!))),
        );
      }
      final sections = groupResults(snap.data!.items);
      final albums = snap.data!.albums;
      if (sections.isEmpty && albums.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _filters.kind == SearchKind.artists && _filters.text.trim().isEmpty
                  ? 'Type an artist\'s name'
                  : 'Nothing found. Try fewer words or filters.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      final theme = Theme.of(context);
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Albums go after the artists, before the tracks.
          for (final (title, items) in [
            ...sections.where((s) => s.$1 == 'Movies' || s.$1 == 'Shows' || s.$1 == 'Episodes' || s.$1 == 'Artists'),
            if (albums.isNotEmpty) ('Albums', const <JellyfinItem>[]),
            ...sections.where((s) => !{'Movies', 'Shows', 'Episodes', 'Artists'}.contains(s.$1)),
          ]) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                '$title · ${title == 'Albums' ? albums.length : items.length}',
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            if (title == 'Albums')
              for (final a in albums)
                ListTile(
                  leading: ArtThumb(url: client.imageUrl(a.cover, height: 168), headers: client.headers, icon: Icons.album),
                  title: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [a.artist, a.year?.toString(), '${a.tracks.length} ${a.tracks.length == 1 ? 'track' : 'tracks'}']
                        .whereType<String>()
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _openAlbum(a),
                  onLongPress: () => addToPlaylist(context, client, items: a.tracks),
                ),
            for (final item in items)
              ListTile(
                leading: ArtThumb(
                  url: item.isPhoto ? client.photoUrl(item, maxSide: 200) : client.imageUrl(item, height: 168),
                  headers: client.headers,
                  icon: itemIcon(item),
                  aspect: item.imageAspect,
                ),
                title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: switch (resultSubtitle(item)) {
                  '' => null,
                  final s => Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                },
                onTap: () => _open(items, item),
                onLongPress: item.isPlayable || item.type == 'MusicAlbum' ? () => itemActions(items, item) : null,
              ),
          ],
        ],
      );
    },
  );

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
