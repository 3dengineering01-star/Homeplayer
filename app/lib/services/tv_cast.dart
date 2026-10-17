import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/common.dart';
import '../api/dlna.dart';

/// Whether [a] and [b] lead to the same file on the server, whatever address each uses: the
/// stream links end in `/<item id>/stream`.
bool sameFile(Uri a, Uri b) {
  List<String> tail(Uri u) => u.pathSegments.length < 2 ? u.pathSegments : u.pathSegments.sublist(u.pathSegments.length - 2);
  return listEquals(tail(a), tail(b));
}

/// One video or track playing on a TV: starts it there, follows where it is, sends the
/// remote's buttons and tells the server how far it got, as the phone's own player does. It
/// goes on after the remote screen closes, until the TV stops or another cast starts.
class TvCast extends ChangeNotifier {
  TvCast({
    required this.tv,
    required this.tvName,
    required this.item,
    this.pollEvery = const Duration(seconds: 2),
    this.waitStep = const Duration(milliseconds: 500),
    this.openTimeout = const Duration(seconds: 20),
    this.stoppedGrace = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

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

  final DateTime Function() _clock;

  /// When the TV last answered, and whether it was playing then: a phone asleep hears nothing
  /// for a while, and the TV may finish the video meanwhile.
  DateTime? _heard;
  bool _wasPlaying = false;

  /// The cast the app follows now; null when nothing plays on a TV.
  static final active = ValueNotifier<TvCast?>(null);

  /// Whether the remote screen is open: the bar at the bottom of the app then hides.
  static final remoteShown = ValueNotifier<bool>(false);

  /// The cast of [url]'s file, if one plays on a TV now.
  static TvCast? playing(Uri url) {
    final c = active.value;
    return c != null && !c.ended && sameFile(c.item.url, url) ? c : null;
  }

  TvState state = TvState.loading;
  Duration position = Duration.zero;
  Duration? duration;

  /// Why the TV does not play; null while all is well.
  String? error;

  /// Played to the end or stopped on the TV itself.
  bool get ended => _ended;
  bool _ended = false;

  Timer? _timer;
  bool _reportedStart = false, _reportedStop = false, _polling = false, _disposed = false, _released = false;
  int _polls = 0;

  /// Polls in a row the TV did not answer.
  int _missed = 0;

  /// After this many unanswered polls the remote says the TV is gone (it may come back).
  static const missedToLost = 3;

  /// Longer than the TV ever takes to answer: without an answer for this long, the phone slept.
  static const silence = Duration(seconds: 20);

  static const lostMessage = 'The TV stopped answering. It may have closed the video, gone to standby or lost the Wi-Fi.';

  /// Sends the file to the TV and starts it at [startAt]. On failure [error] says why.
  Future<void> start({Duration startAt = Duration.zero}) async {
    // One cast at a time: the one before stops being followed (and reports where it was).
    final before = active.value;
    if (before != null && before != this) before.release();
    active.value = this;
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
    while (watch.elapsed < openTimeout && !_released) {
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
    if (_polling || _ended || _released) return;
    _polling = true;
    try {
      final s = await tv.state();
      final p = await tv.position();
      state = s;
      final stopped = s == TvState.stopped || s == TvState.noMedia;
      // A stopped TV says 0:00: the place is the last one heard.
      if (p.position != null && !stopped) position = p.position!;
      if (p.duration != null && p.duration! > Duration.zero) duration = p.duration;
      _missed = 0;
      if (error == lostMessage) error = null;
      final now = _clock(), heard = _heard;
      if (stopped && _wasPlaying && heard != null) {
        // After a long silence (the phone was asleep) the TV went on playing meanwhile: the
        // server gets where it must have got to, up to the end.
        position = estimatedPlace(position, now.difference(heard), duration, silence: silence);
      }
      _heard = now;
      _wasPlaying = s == TvState.playing;
      if (stopped) {
        _ended = true;
        release();
      } else if (++_polls % 5 == 0) {
        unawaited(item.reporter?.progress(position, paused: s == TvState.paused));
      }
      _notify();
    } catch (e) {
      debugPrint('homeplay TV poll failed: $e');
      if (++_missed == missedToLost) {
        error = lostMessage;
        state = TvState.unknown;
        _notify();
      }
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
    release();
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
    release();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Stops following the TV, which may go on playing: the server gets the last place known,
  /// and the app no longer shows this cast.
  void release() {
    if (_released) return;
    _released = true;
    _timer?.cancel();
    unawaited(_reportStop());
    tv.close();
    if (active.value == this) active.value = null;
  }

  @override
  void dispose() {
    _disposed = true;
    release();
    super.dispose();
  }
}

/// Where a TV that was playing at [last] must have got to after [gap] without an answer; [last]
/// itself when the gap is no longer than [silence] (an ordinary stop). Never past [duration].
Duration estimatedPlace(Duration last, Duration gap, Duration? duration, {required Duration silence}) {
  if (gap <= silence) return last;
  final guess = last + gap;
  return duration != null && guess > duration ? duration : guess;
}
