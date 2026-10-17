import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/common.dart';
import '../api/dlna.dart';

/// One video or track playing on a TV: starts it there, follows where it is, sends the
/// remote's buttons and tells the server how far it got, as the phone's own player does.
class TvCast extends ChangeNotifier {
  TvCast({
    required this.tv,
    required this.tvName,
    required this.item,
    this.pollEvery = const Duration(seconds: 1),
    this.waitStep = const Duration(milliseconds: 500),
    this.openTimeout = const Duration(seconds: 20),
    this.stoppedGrace = const Duration(seconds: 5),
  });

  final TvControl tv;
  final String tvName;
  final PlayItem item;
  final Duration pollEvery;
  final Duration waitStep;

  /// How long a TV may take to open the file before the app gives up.
  final Duration openTimeout;

  /// Some TVs report "stopped" for a moment before they start loading; after this it means
  /// they could not open the file.
  final Duration stoppedGrace;

  TvState state = TvState.loading;
  Duration position = Duration.zero;
  Duration? duration;

  /// Why the TV does not play; null while all is well.
  String? error;

  /// Played to the end or stopped on the TV itself.
  bool get ended => _ended;
  bool _ended = false;

  Timer? _timer;
  bool _reportedStart = false, _reportedStop = false, _polling = false, _disposed = false;
  int _polls = 0;

  /// Sends the file to the TV and starts it at [startAt]. On failure [error] says why.
  Future<void> start({Duration startAt = Duration.zero}) async {
    try {
      final metadata = didlLite(
        title: item.title,
        url: item.url,
        mime: mimeFor(item.container, isVideo: item.isVideo),
        isVideo: item.isVideo,
      );
      // A TV that still shows something else may refuse a new file until stopped.
      try {
        await tv.stop();
      } catch (_) {}
      await tv.open(item.url, metadata);
      await tv.play();
      if (!await _waitPlaying()) {
        _fail('The TV could not open the file. It must reach the server at ${item.url.host}: '
            'add the server by its home address (for example 192.168.1.10:8096) and try again.');
        return;
      }
      if (startAt > Duration.zero) {
        try {
          await tv.seek(startAt);
          position = startAt;
        } catch (e) {
          debugPrint('homeplay TV seek to the resume point failed: $e');
        }
      }
      _reportedStart = true;
      unawaited(item.reporter?.started(position));
      _timer = Timer.periodic(pollEvery, (_) => poll());
      _notify();
    } catch (e) {
      _fail(e is DlnaException ? e.message : 'The TV did not answer. Is it on and on the same Wi-Fi?');
      debugPrint('homeplay TV start failed: $e');
    }
  }

  Future<bool> _waitPlaying() async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < openTimeout && !_disposed) {
      final s = await tv.state().catchError((_) => TvState.unknown);
      state = s;
      if (s == TvState.playing) return true;
      if ((s == TvState.stopped || s == TvState.noMedia) && watch.elapsed >= stoppedGrace) return false;
      await Future.delayed(waitStep);
    }
    return false;
  }

  /// Asks the TV where it is; called every [pollEvery].
  Future<void> poll() async {
    if (_polling || _ended || _disposed) return;
    _polling = true;
    try {
      final s = await tv.state();
      final p = await tv.position();
      state = s;
      if (p.position != null) position = p.position!;
      if (p.duration != null && p.duration! > Duration.zero) duration = p.duration;
      if (s == TvState.stopped || s == TvState.noMedia) {
        _ended = true;
        _timer?.cancel();
        await _reportStop();
      } else if (++_polls % 10 == 0) {
        unawaited(item.reporter?.progress(position, paused: s == TvState.paused));
      }
      _notify();
    } catch (e) {
      debugPrint('homeplay TV poll failed: $e');
    } finally {
      _polling = false;
    }
  }

  Future<void> togglePause() => _command(() => state == TvState.playing ? tv.pause() : tv.play(),
      then: () => state = state == TvState.playing ? TvState.paused : TvState.playing);

  Future<void> seekTo(Duration to) {
    final d = duration;
    final target = to < Duration.zero ? Duration.zero : (d != null && to > d ? d : to);
    return _command(() => tv.seek(target), then: () => position = target);
  }

  Future<void> seekBy(Duration delta) => seekTo(position + delta);

  /// Stops the TV and reports the place to the server.
  Future<void> stop() async {
    _timer?.cancel();
    try {
      await tv.stop();
    } catch (e) {
      debugPrint('homeplay TV stop failed: $e');
    }
    _ended = true;
    state = TvState.stopped;
    await _reportStop();
    _notify();
  }

  Future<void> _command(Future<void> Function() send, {required void Function() then}) async {
    try {
      await send();
      then();
      error = null;
    } catch (e) {
      error = e is DlnaException ? e.message : 'The TV did not answer.';
    }
    _notify();
  }

  Future<void> _reportStop() async {
    if (!_reportedStart || _reportedStop) return;
    _reportedStop = true;
    await item.reporter?.stopped(position, duration: duration);
  }

  void _fail(String message) {
    error = message;
    state = TvState.stopped;
    _ended = true;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Leaving the remote keeps the TV playing; the server gets the last place it knows.
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_reportStop());
    tv.close();
    super.dispose();
  }
}
