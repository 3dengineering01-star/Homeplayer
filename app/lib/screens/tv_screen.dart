import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/dlna.dart';
import '../services/licence.dart';
import '../services/pro.dart';
import '../services/tv_cast.dart';
import '../widgets/artwork.dart';
import 'pro_screen.dart';

/// Picks a TV and opens the remote for [item] on it, from [startAt]. With [replace] the remote
/// takes the place of the current screen (the player).
/// When the same file already plays on a TV, its remote opens instead: nothing starts over.
Future<void> playOnTv(BuildContext context, PlayItem item, {Duration startAt = Duration.zero, bool replace = false}) async {
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (await showTvRemote(context, item.url, replace: replace)) return;
  if (!context.mounted) return;
  if (!canPlayOnTv(item)) {
    messenger.showSnackBar(SnackBar(
        content: Text(item.url.scheme == 'file'
            ? 'A download lives on the phone, the TV cannot open it. Play it from the server instead.'
            : 'The server is converting this video for the connection. Choose the original quality first.')));
    return;
  }
  // Play on TV is part of OwnMedia Pro.
  if (!await Pro.instance.mayUseAny()) {
    if (!context.mounted) return;
    final bought = await nav.push<bool>(MaterialPageRoute(builder: (_) => const ProScreen(feature: ProFeature.tv)));
    if (bought != true || !context.mounted) return;
  }
  if (!context.mounted) return;
  final device = await pickTv(context);
  if (device == null) return;
  final url = await item.tvUrl?.call().catchError((_) => item.url) ?? item.url;
  final cast = TvCast(tv: DlnaTv(device), tvName: device.name, item: item.copyWith(url: url));
  final route = MaterialPageRoute<void>(builder: (_) => TvRemoteScreen(cast: cast, startAt: startAt));
  await (replace ? nav.pushReplacement(route) : nav.push(route));
}

/// Opens the remote of what plays on a TV, if it is [url]'s file; false when it is not.
Future<bool> showTvRemote(BuildContext context, Uri url, {bool replace = false}) async {
  final cast = TvCast.playing(url);
  if (cast == null) return false;
  final route = MaterialPageRoute<void>(builder: (_) => TvRemoteScreen(cast: cast, start: false));
  final nav = Navigator.of(context);
  await (replace ? nav.pushReplacement(route) : nav.push(route));
  return true;
}

/// Only a file the server sends as it is: a TV cannot open a download on the phone, and a
/// converted stream belongs to the phone's own playback session.
bool canPlayOnTv(PlayItem item) => (item.url.scheme == 'http' || item.url.scheme == 'https') && item.convertedTo == null;

/// The TVs on this Wi-Fi to choose from; null when dismissed.
Future<TvDevice?> pickTv(BuildContext context, {Future<List<TvDevice>> Function()? search}) =>
    showModalBottomSheet<TvDevice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TvPicker(search: search ?? discoverTvs),
    );

class _TvPicker extends StatefulWidget {
  const _TvPicker({required this.search});

  final Future<List<TvDevice>> Function() search;

  @override
  State<_TvPicker> createState() => _TvPickerState();
}

class _TvPickerState extends State<_TvPicker> {
  List<TvDevice>? _found;

  @override
  void initState() {
    super.initState();
    _look();
  }

  Future<void> _look() async {
    setState(() => _found = null);
    final found = await widget.search();
    if (mounted) setState(() => _found = found);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = _found;
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Play on TV', style: theme.textTheme.titleMedium),
        ),
        if (found == null)
          const ListTile(
            leading: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            title: Text('Looking for TVs on this Wi-Fi…'),
          )
        else if (found.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'No TV found. Turn the TV on and connect it to the same Wi-Fi as the phone. '
              'Most TVs (LG, Samsung, Sony, Philips) accept videos from phones when on; on some, '
              'connecting with phones has to be allowed in the TV\'s network settings, '
              'e.g. "LG Connect Apps" on LG.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (final tv in found)
            ListTile(
              leading: const Icon(Icons.tv),
              title: Text(tv.name),
              subtitle: tv.model.isEmpty ? null : Text(tv.model),
              onTap: () => Navigator.pop(context, tv),
            ),
        if (found != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: _look, icon: const Icon(Icons.refresh), label: const Text('Search again')),
            ),
          ),
      ]),
    );
  }
}

/// The phone as a remote for what plays on the TV. Leaving it keeps the TV playing, and the
/// bar at the bottom of the app brings it back.
class TvRemoteScreen extends StatefulWidget {
  const TvRemoteScreen({super.key, required this.cast, this.startAt = Duration.zero, this.start = true});

  final TvCast cast;
  final Duration startAt;

  /// Whether to send the file to the TV; false to open the remote of a cast already playing.
  final bool start;

  @override
  State<TvRemoteScreen> createState() => _TvRemoteScreenState();
}

class _TvRemoteScreenState extends State<TvRemoteScreen> {
  TvCast get _cast => widget.cast;

  /// Where the slider is while a finger drags it.
  double? _dragging;

  @override
  void initState() {
    super.initState();
    if (widget.start) _cast.start(startAt: widget.startAt);
    TvCast.remoteShown.value = true;
  }

  @override
  void dispose() {
    TvCast.remoteShown.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _cast.item;
    return Scaffold(
      appBar: AppBar(title: Text('On ${_cast.tvName}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListenableBuilder(
        listenable: _cast,
        builder: (context, _) {
          final duration = _cast.duration;
          final total = duration?.inMilliseconds.toDouble() ?? 0;
          final at = (_dragging ?? _cast.position.inMilliseconds.toDouble()).clamp(0.0, total > 0 ? total : 0.0);
          final loading = _cast.state == TvState.loading || _cast.state == TvState.unknown;
          final ready = !_cast.ended && !loading;
          return ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 32), children: [
            Center(
              child: Container(
                width: 220,
                height: item.isVideo ? 124 : 220,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                // A download's own cover, or the server's (kept on the phone).
                child: artworkImage(item, fallback: Icon(Icons.tv, size: 56, color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
            const SizedBox(height: 20),
            Text(item.title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            if (item.subtitle != null)
              Text(item.subtitle!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Text(
              _cast.error ??
                  (_cast.ended
                      ? 'Stopped'
                      : loading
                          ? 'Opening on the TV…'
                          : _cast.state == TvState.paused
                              ? 'Paused on the TV'
                              : 'Playing on the TV'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _cast.error != null ? theme.colorScheme.error : theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text(
              // The TV fetches the file itself: over the home network at full speed, or through the
              // internet (the server's internet address), where large videos may stop to load.
              isHomeHost(item.url.host)
                  ? 'The TV takes the video from the server over your home network'
                  : 'The TV takes the video over the internet: large videos may pause to load. '
                      'At home, the phone finds the server on the Wi-Fi when both are on it.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Slider(
              value: at,
              max: total > 0 ? total : 1,
              onChanged: ready && total > 0 ? (v) => setState(() => _dragging = v) : null,
              onChangeEnd: ready && total > 0
                  ? (v) {
                      setState(() => _dragging = null);
                      _cast.seekTo(Duration(milliseconds: v.round()));
                    }
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Text(formatDuration(Duration(milliseconds: at.round()))),
                const Spacer(),
                Text(duration == null ? '' : formatDuration(duration)),
              ]),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                tooltip: '10 seconds back',
                iconSize: 36,
                onPressed: ready ? () => _cast.seekBy(const Duration(seconds: -10)) : null,
                icon: const Icon(Icons.replay_10),
              ),
              const SizedBox(width: 16),
              IconButton.filled(
                tooltip: _cast.state == TvState.playing ? 'Pause' : 'Play',
                iconSize: 48,
                onPressed: ready ? _cast.togglePause : null,
                icon: Icon(_cast.state == TvState.playing ? Icons.pause : Icons.play_arrow),
              ),
              const SizedBox(width: 16),
              IconButton(
                tooltip: '10 seconds forward',
                iconSize: 36,
                onPressed: ready ? () => _cast.seekBy(const Duration(seconds: 10)) : null,
                icon: const Icon(Icons.forward_10),
              ),
            ]),
            const SizedBox(height: 24),
            Center(
              child: _cast.ended
                  ? FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        await _cast.stop();
                        nav.maybePop();
                      },
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop on TV'),
                    ),
            ),
            if (!_cast.ended) ...[
              const SizedBox(height: 12),
              Text('Going back keeps it playing on the TV. The bar at the bottom brings this remote back.',
                  textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ]);
        },
      ),
    );
  }
}
