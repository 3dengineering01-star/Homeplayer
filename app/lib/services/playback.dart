import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api/common.dart';

/// The one player of the app. It outlives the player screen, so music keeps going in the
/// background, and it drives the media notification, lock screen and headset buttons.
class Playback extends BaseAudioHandler with SeekHandler {
  Playback._() {
    _listen();
  }

  static late final Playback instance;

  static Future<void> init() async {
    instance = await AudioService.init(
      builder: Playback._,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.homeplay.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationIcon: 'drawable/ic_launcher_foreground',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    await instance._initSession();
  }

  // libass keeps ASS styling (colour, position, fades); it needs a bundled font on Android.
  final Player player = Player(
    configuration: const PlayerConfiguration(
      libass: true,
      libassAndroidFont: 'assets/fonts/roboto-regular.ttf',
      libassAndroidFontName: 'Roboto',
      logLevel: MPVLogLevel.warn,
    ),
  );

  VideoController? _video;
  VideoController get video => _video ??= VideoController(player);

  /// What is queued, and which of it is playing.
  final ValueNotifier<List<PlayItem>> items = ValueNotifier(const []);
  final ValueNotifier<int> current = ValueNotifier(0);

  /// True while the full player screen is open; the mini player hides then.
  final ValueNotifier<bool> screenOpen = ValueNotifier(false);

  final _notices = StreamController<String>.broadcast();
  Stream<String> get notices => _notices.stream;

  PlayItem? get currentItem => items.value.isEmpty ? null : items.value[current.value];

  final Set<int> _audioSwitched = {};

  // Server reports: which queue entries got their stop report, and a heartbeat for progress.
  final Set<int> _stopReported = {};
  Duration _lastPosition = Duration.zero;
  Timer? _heartbeat;
  Future<void> _lastStopReport = Future.value();
  Timer? _cacheLog;

  /// Completes once the server has the latest stop report, so a list reloaded after it
  /// shows the right resume point.
  Future<void> get reportsSent => _lastStopReport.timeout(const Duration(seconds: 3), onTimeout: () {});

  AudioSession? _session;
  bool _resumeAfterInterruption = false;

  /// Plays [queueItems] from [index], optionally from [startAt] (a resume point).
  Future<void> start(List<PlayItem> queueItems, int index, {Duration? startAt}) async {
    _endReport(current.value, player.state.position);
    _audioSwitched.clear();
    _stopReported.clear();
    items.value = queueItems;
    current.value = index;
    queue.add([for (final i in queueItems) _mediaItem(i)]);
    mediaItem.add(_mediaItem(queueItems[index]));
    await _session?.setActive(true);
    // media_kit keeps video off (vid=no) until a video output is attached; a file without
    // sound would otherwise end at once with "no audio or video streams selected".
    if (queueItems.any((i) => i.isVideo)) await video.platform.future;
    await player.open(Playlist(
      [
        for (var n = 0; n < queueItems.length; n++)
          Media(queueItems[n].url.toString(), httpHeaders: queueItems[n].headers, start: n == index ? startAt : null),
      ],
      index: index,
    ));
    _notice();
    _beginReport(startAt ?? Duration.zero);
    _heartbeat ??= Timer.periodic(const Duration(seconds: 10), (_) => _reportProgress());
    if (kDebugMode) _cacheLog ??= Timer.periodic(const Duration(seconds: 5), (_) => _logCache());
  }

  @override
  Future<void> play() async {
    await _session?.setActive(true);
    await player.play();
  }

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) async {
    await player.seek(position);
    playbackState.add(playbackState.value.copyWith(updatePosition: position));
    _reportProgress(position);
  }

  @override
  Future<void> skipToNext() {
    _endReport(current.value, player.state.position);
    return player.next();
  }

  @override
  Future<void> skipToPrevious() {
    _endReport(current.value, player.state.position);
    return player.previous();
  }

  @override
  Future<void> skipToQueueItem(int index) {
    _endReport(current.value, player.state.position);
    return player.jump(index);
  }

  @override
  Future<void> stop() async {
    _endReport(current.value, player.state.position);
    _heartbeat?.cancel();
    _heartbeat = null;
    _cacheLog?.cancel();
    _cacheLog = null;
    await player.stop();
    items.value = const [];
    current.value = 0;
    queue.add(const []);
    mediaItem.add(null);
    await _session?.setActive(false);
    _broadcast();
    await super.stop();
  }

  void _beginReport(Duration position) {
    _stopReported.remove(current.value); // it may be played again after going back
    currentItem?.reporter?.started(position);
  }

  void _reportProgress([Duration? position]) {
    if (currentItem == null || _stopReported.contains(current.value)) return;
    currentItem?.reporter?.progress(position ?? player.state.position, paused: !player.state.playing);
  }

  /// Once per queue entry: when it is left, skipped or finished.
  void _endReport(int index, Duration position) {
    if (index >= items.value.length || !_stopReported.add(index)) return;
    _lastStopReport = items.value[index].reporter?.stopped(position) ?? Future.value();
  }

  MediaItem _mediaItem(PlayItem i) => MediaItem(
        id: i.url.toString(),
        title: i.title,
        artist: i.subtitle,
        artUri: i.artwork,
        artHeaders: i.headers.isEmpty ? null : i.headers,
      );

  void _notice() {
    final notice = currentItem?.notice;
    if (notice != null) _notices.add(notice);
  }

  void _listen() {
    final s = player.stream;
    s.playlist.listen((p) {
      if (items.value.isEmpty || p.index < 0 || p.index >= items.value.length || p.index == current.value) return;
      // Not reported yet means the previous entry played to its end.
      _endReport(current.value, mediaItem.value?.duration ?? _lastPosition);
      current.value = p.index;
      mediaItem.add(_mediaItem(items.value[p.index]));
      _notice();
      _broadcast();
      _beginReport(Duration.zero);
    });
    s.position.listen((p) => _lastPosition = p);
    s.duration.listen((d) {
      final m = mediaItem.value;
      if (m != null && d > Duration.zero) mediaItem.add(m.copyWith(duration: d));
      if (kDebugMode && d > Duration.zero) _logDecoders();
    });
    // Switch away from an audio track this libmpv can't decode, once per queue entry.
    s.tracks.listen((t) {
      final want = currentItem?.audioTrackId;
      if (want == null || _audioSwitched.contains(current.value)) return;
      final track = t.audio.where((a) => a.id == want).firstOrNull;
      if (track == null) return;
      _audioSwitched.add(current.value);
      player.setAudioTrack(track);
    });
    s.playing.listen((_) {
      _broadcast();
      _reportProgress();
    });
    s.buffering.listen((_) => _broadcast());
    s.completed.listen((done) {
      _broadcast();
      if (done) _endReport(current.value, mediaItem.value?.duration ?? _lastPosition);
    });
    s.log.listen((l) => debugPrint('homeplay mpv [${l.level}] ${l.prefix}: ${l.text.trim()}'));
    // mpv reports recoverable problems here too (e.g. a hardware decoder it then falls back from),
    // so they are only logged.
    s.error.listen((e) => debugPrint('homeplay player error: $e'));
  }

  /// Tells the notification and the lock screen what is going on.
  void _broadcast() {
    final st = player.state;
    final count = items.value.length;
    final hasPrev = current.value > 0;
    final hasNext = current.value < count - 1;
    final controls = [
      if (hasPrev) MediaControl.skipToPrevious,
      st.playing ? MediaControl.pause : MediaControl.play,
      if (hasNext) MediaControl.skipToNext,
      MediaControl.stop,
    ];
    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: [for (var i = 0; i < controls.length - 1; i++) i],
      processingState: count == 0
          ? AudioProcessingState.idle
          : st.completed
              ? AudioProcessingState.completed
              : st.buffering
                  ? AudioProcessingState.buffering
                  : AudioProcessingState.ready,
      playing: st.playing,
      updatePosition: st.position,
      bufferedPosition: st.buffer,
      speed: st.rate,
      queueIndex: count == 0 ? null : current.value,
    ));
  }

  /// Pause for calls and other apps, and when headphones are unplugged.
  Future<void> _initSession() async {
    final session = _session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.becomingNoisyEventStream.listen((_) => pause());
    session.interruptionEventStream.listen((e) {
      if (e.begin) {
        if (e.type == AudioInterruptionType.duck) {
          player.setVolume(30);
        } else {
          _resumeAfterInterruption = player.state.playing;
          pause();
        }
      } else {
        if (e.type == AudioInterruptionType.duck) {
          player.setVolume(100);
        } else if (e.type == AudioInterruptionType.pause && _resumeAfterInterruption) {
          play();
        }
        _resumeAfterInterruption = false;
      }
    });
  }

  /// Debug builds: how fast data arrives and how much is buffered, to tell a slow network
  /// from a slow decoder.
  Future<void> _logCache() async {
    if (items.value.isEmpty) return;
    final native = player.platform as NativePlayer;
    final speed = int.tryParse(await native.getProperty('cache-speed')) ?? 0;
    final ahead = await native.getProperty('demuxer-cache-duration');
    final st = player.state;
    debugPrint('homeplay cache: ${(speed * 8 / 1e6).toStringAsFixed(1)} Mbit/s, ${ahead}s ahead, '
        'pos=${st.position.inSeconds}s buffering=${st.buffering} playing=${st.playing}');
  }

  /// Debug builds: which decoders this libmpv has and which one is in use.
  Future<void> _logDecoders() async {
    final native = player.platform as NativePlayer;
    await Future.delayed(const Duration(seconds: 1));
    final hwdec = await native.getProperty('hwdec-current');
    final codec = await native.getProperty('video-codec');
    final audio = await native.getProperty('audio-codec-name');
    final list = await native.getProperty('decoder-list');
    final names = RegExp(r'"codec":"([^"]+)"').allMatches(list).map((m) => m.group(1)).toSet();
    const wanted = ['truehd', 'mlp', 'dts', 'eac3', 'ac3', 'aac', 'flac', 'opus', 'hevc', 'av1', 'vp9', 'h264'];
    debugPrint('homeplay decoders: video=$codec hwdec=$hwdec audio=$audio; '
        'available: ${wanted.map((c) => '$c=${names.contains(c) ? 'yes' : 'NO'}').join(' ')}');
  }
}
