import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../widgets/media_cards.dart';
import 'jellyfin_actions.dart';

/// A movie's or series' page: the backdrop, what it is about, play or resume, and for a
/// series its seasons and episodes.
class ItemDetailsScreen extends StatefulWidget {
  const ItemDetailsScreen({super.key, required this.client, required this.item});

  final JellyfinClient client;

  /// What the list knew; the full details load on the page.
  final JellyfinItem item;

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> with JellyfinActions {
  @override
  JellyfinClient get client => widget.client;

  late JellyfinItem _item = widget.item;
  List<JellyfinItem> _seasons = const [];
  JellyfinItem? _season;
  List<JellyfinItem>? _episodes;
  Object? _error;
  bool _overviewOpen = false;

  bool get _isSeries => _item.type == 'Series';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void refresh() => _load();

  Future<void> _load() async {
    try {
      final item = await client.item(widget.item.id);
      if (!mounted) return;
      setState(() {
        _item = item;
        _error = null;
      });
      if (item.type == 'Series') {
        final seasons = await client.seasons(item.id);
        if (!mounted) return;
        // Stay on the season being looked at; at first, the first one not fully watched.
        final keep = seasons.where((s) => s.id == _season?.id).firstOrNull;
        final season = keep ?? seasons.where((s) => !s.played).firstOrNull ?? seasons.firstOrNull;
        setState(() => _seasons = seasons);
        if (season != null) await _showSeason(season);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _showSeason(JellyfinItem season) async {
    setState(() {
      _season = season;
      _episodes = null;
    });
    try {
      final episodes = await client.episodes(_item.id, season.id);
      if (mounted && _season?.id == season.id) setState(() => _episodes = episodes);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// For a series: the episode the Play button plays, the one started or the first not watched.
  JellyfinItem? get _nextEpisode {
    final eps = _episodes;
    if (eps == null || eps.isEmpty) return null;
    return eps.where((e) => e.progress != null && !e.played).firstOrNull ?? eps.where((e) => !e.played).firstOrNull ?? eps.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final backdrop = client.backdropUrl(_item, width: 1280);
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 240,
          backgroundColor: scheme.surface,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              NetImage(url: backdrop, headers: client.headers, icon: itemTypeIcon(_item)),
              // Fades into the page so the title below reads on any picture.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black38, Colors.transparent, scheme.surface],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: _header(theme)),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(describeError(_error!), style: TextStyle(color: scheme.error)),
            ),
          ),
        if (_isSeries) ..._seriesSlivers(theme),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ]),
    );
  }

  Widget _header(ThemeData theme) {
    final scheme = theme.colorScheme;
    final item = _item;
    final meta = [
      if (item.year != null) '${item.year}',
      if (item.runTime != null && !_isSeries) runTimeLabel(item.runTime!),
      if (_isSeries && _seasons.isNotEmpty) '${_seasons.length} ${_seasons.length == 1 ? 'season' : 'seasons'}',
      if (item.ageRating != null && item.ageRating!.isNotEmpty) item.ageRating!,
    ];
    final overview = item.overview;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SizedBox(
            width: 104,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Hero(
                  tag: 'poster-${widget.item.id}',
                  child: NetImage(url: client.imageUrl(item, height: 420), headers: client.headers, icon: itemTypeIcon(item)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final m in meta)
                  Text(m, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                if (item.rating != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF5B301)),
                    const SizedBox(width: 2),
                    Text(item.rating!.toStringAsFixed(1), style: theme.textTheme.bodyMedium),
                  ]),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        _buttons(theme),
        if (item.genres.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in item.genres.take(5))
              Chip(label: Text(g), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
          ]),
        ],
        if (overview != null && overview.isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _overviewOpen = !_overviewOpen),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: Text(
                overview,
                maxLines: _overviewOpen ? null : 4,
                overflow: _overviewOpen ? TextOverflow.visible : TextOverflow.fade,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buttons(ThemeData theme) {
    final item = _isSeries ? _nextEpisode : _item;
    final resumeAt = item == null || item.played ? Duration.zero : item.resumePosition;
    final label = item == null
        ? 'Play'
        : _isSeries
            ? '${resumeAt > Duration.zero ? 'Resume' : 'Play'} '
                '${item.seasonNumber != null && item.indexNumber != null ? 'S${item.seasonNumber}E${item.indexNumber}' : item.name}'
            : resumeAt > Duration.zero
                ? 'Resume ${formatDuration(resumeAt)}'
                : 'Play';
    final list = _isSeries ? (_episodes ?? const <JellyfinItem>[]) : [_item];
    return Row(children: [
      Expanded(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: item == null || (_isSeries && _episodes == null) ? null : () => openItem(list, item),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        tooltip: 'More',
        onPressed: () => itemActions(list, _isSeries ? _item : item ?? _item),
        icon: const Icon(Icons.more_horiz),
      ),
    ]);
  }

  List<Widget> _seriesSlivers(ThemeData theme) {
    final episodes = _episodes;
    return [
      if (_seasons.length > 1)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              children: [
                for (final s in _seasons)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.name),
                      selected: s.id == _season?.id,
                      onSelected: (_) => _showSeason(s),
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (episodes == null)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
      else
        SliverList.builder(
          itemCount: episodes.length,
          itemBuilder: (context, i) => _EpisodeRow(
            episode: episodes[i],
            client: client,
            onTap: () => openItem(episodes, episodes[i]),
            onLongPress: () => itemActions(episodes, episodes[i]),
          ),
        ),
    ];
  }
}

/// An episode: its still with progress, number and name, length and a line of the plot.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.client, required this.onTap, required this.onLongPress});

  final JellyfinItem episode;
  final JellyfinClient client;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = episode;
    final progress = e.played ? null : e.progress;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 140,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(fit: StackFit.expand, children: [
                  NetImage(url: client.wideUrl(e, width: 320), headers: client.headers, icon: Icons.tv),
                  if (e.played)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: theme.colorScheme.primary,
                        child: Icon(Icons.check, size: 14, color: theme.colorScheme.onPrimary, semanticLabel: 'Watched'),
                      ),
                    ),
                  if (progress != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: Colors.black38),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e.indexNumber != null ? '${e.indexNumber}. ' : ''}${e.name}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              if (e.runTime != null)
                Text(runTimeLabel(e.runTime!),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (e.overview != null && e.overview!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(e.overview!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
