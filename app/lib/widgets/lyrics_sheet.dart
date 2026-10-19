import 'dart:async';

import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/lyrics.dart';
import '../services/playback.dart';
import '../services/track_lookup.dart';

/// The words of the song playing, from its server. Timed lyrics follow the music: the line
/// sung now is lit and kept in view, a tap on a line jumps there.
void showLyricsSheet(BuildContext context, Playback pb) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => _LyricsView(pb: pb, scroll: scroll),
    ),
  );
}

// Asked once per queue entry while the app runs; reopening the sheet shows them at once.
final _asked = Expando<Future<Lyrics?>>();

class _LyricsView extends StatefulWidget {
  const _LyricsView({required this.pb, required this.scroll});
  final Playback pb;
  final ScrollController scroll;

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  PlayItem? _item;
  Future<Lyrics?>? _lyrics;
  Lyrics? _shown;
  int _line = -1;
  List<GlobalKey> _keys = const [];
  StreamSubscription<Duration>? _position;

  @override
  void initState() {
    super.initState();
    widget.pb.current.addListener(_load);
    widget.pb.items.addListener(_load);
    _position = widget.pb.player.stream.position.listen(_follow);
    _load();
  }

  @override
  void dispose() {
    widget.pb.current.removeListener(_load);
    widget.pb.items.removeListener(_load);
    _position?.cancel();
    super.dispose();
  }

  void _load() {
    final item = widget.pb.currentItem;
    if (item == null || identical(item, _item)) return;
    final lyrics = _asked[item] ??= TrackLookup.lyrics(item);
    setState(() {
      _item = item;
      _lyrics = lyrics;
      _shown = null;
      _line = -1;
    });
    lyrics.then((l) {
      if (!mounted || !identical(_item, item)) return;
      setState(() {
        _shown = l;
        _keys = [for (final _ in l?.lines ?? const []) GlobalKey()];
      });
      _follow(widget.pb.player.state.position);
    }, onError: (_) {});
  }

  void _follow(Duration position) {
    final l = _shown;
    if (l == null || !l.synced) return;
    final line = currentLyricLine(l.lines, position);
    if (line == _line) return;
    setState(() => _line = line);
    if (line < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = _keys[line].currentContext;
      if (at != null && mounted) {
        Scrollable.ensureVisible(at, alignment: 0.35, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<Lyrics?>(
      future: _lyrics,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return _message(context, 'Lyrics could not be loaded', describeError(s.error!));
        final l = _shown ?? s.data;
        if (l == null) {
          return _message(context, 'No lyrics for this song',
              'The server shows lyrics from an .lrc or .txt file next to the song, or from its tags.');
        }
        final muted = theme.colorScheme.onSurface.withValues(alpha: l.synced ? 0.55 : 0.9);
        return SingleChildScrollView(
          controller: widget.scroll,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 160),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_item?.title ?? '', style: theme.textTheme.titleMedium),
            if (_item?.subtitle != null) Text(_item!.subtitle!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            for (final (n, line) in l.lines.indexed)
              InkWell(
                key: n < _keys.length ? _keys[n] : null,
                borderRadius: BorderRadius.circular(8),
                onTap: line.start == null ? null : () => widget.pb.seek(line.start!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
                      fontWeight: n == _line ? FontWeight.w700 : FontWeight.w500,
                      color: n == _line ? theme.colorScheme.primary : muted,
                    ),
                    child: Text(line.text.isEmpty ? '♪' : line.text),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }

  Widget _message(BuildContext context, String title, String details) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lyrics_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(details, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
          ]),
        ),
      );
}
