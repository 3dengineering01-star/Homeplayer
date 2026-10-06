import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../api/subsonic.dart';
import 'account_store.dart';
import 'car_library.dart';
import 'downloads.dart';
import 'quality.dart';
import 'track_choice.dart';
import 'video_tuning.dart';

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
        // Paused: the notification stays but can be swiped away. Stopped: it goes. With the
        // defaults it stayed after Stop, detached from the service and impossible to dismiss.
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
        androidResumeOnClick: false,
      ),
    );
    await instance._initSession();
    final prefs = instance._prefs = await SharedPreferences.getInstance();
    instance.adjust.value = VideoAdjust.fromPrefs(prefs.get);
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

  // Player screens on the navigator: one may open over another (mini player, a list), so a
  // single flag set and cleared by each would say "closed" while one is still showing.
  int _openScreens = 0;

  void screenOpened() => screenOpen.value = ++_openScreens > 0;

  void screenClosed() => screenOpen.value = (_openScreens = (_openScreens - 1).clamp(0, 1 << 30)) > 0;

  final _notices = StreamController<String>.broadcast();
  Stream<String> get notices => _notices.stream;

  PlayItem? get currentItem => items.value.isEmpty ? null : items.value[current.value];

  // Remembered track languages, applied once per queue entry when its tracks are known.
  SharedPreferences? _prefs;
  static const _audioLanguageKey = 'audio_language';
  static const _subtitleLanguageKey = 'subtitle_language';
  final Set<int> _tracksApplied = {};

  // Queue entries whose subtitle files were added to mpv.
  final Set<int> _subtitlesAdded = {};

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

  /// Subtitle size, position and colour, and the subtitle and sound delays of the video player.
  final ValueNotifier<VideoAdjust> adjust = ValueNotifier(const VideoAdjust());

  /// Applies [a] to mpv and keeps what carries over to the next videos.
  Future<void> setAdjust(VideoAdjust a) async {
    final before = adjust.value.mpvProperties;
    adjust.value = a;
    await _applyAdjust(a, only: before);
    final prefs = _prefs;
    if (prefs == null) return;
    for (final e in a.toPrefs().entries) {
      switch (e.value) {
        case final double v:
          await prefs.setDouble(e.key, v);
        case final int v:
          await prefs.setInt(e.key, v);
        case final bool v:
          await prefs.setBool(e.key, v);
      }
    }
  }

  /// Sets [a]'s mpv properties; with [only], just those that differ from it.
  Future<void> _applyAdjust(VideoAdjust a, {Map<String, String>? only}) async {
    final native = player.platform as NativePlayer;
    for (final e in a.mpvProperties.entries) {
      if (only != null && only[e.key] == e.value) continue;
      try {
        await native.setProperty(e.key, e.value);
      } catch (err) {
        debugPrint('homeplay mpv ${e.key} failed: $err');
      }
    }
  }

  /// Plays [queueItems] from [index], optionally from [startAt] (a resume point).
  Future<void> start(List<PlayItem> queueItems, int index, {Duration? startAt}) async {
    _endReport(current.value, player.state.position);
    _tracksApplied.clear();
    _subtitlesAdded.clear();
    _stopReported.clear();
    items.value = queueItems;
    current.value = index;
    queue.add([for (final i in queueItems) _mediaItem(i)]);
    mediaItem.add(_mediaItem(queueItems[index]));
    await _session?.setActive(true);
    // media_kit keeps video off (vid=no) until a video output is attached; a file without
    // sound would otherwise end at once with "no audio or video streams selected".
    if (queueItems.any((i) => i.isVideo)) {
      await video.platform.future;
      // media_kit hands MPEG-4 Part 2 (Xvid/DivX) and MPEG-2 to MediaCodec too; on the Pixel
      // that stutters (frames out of order, no position) while software decoding of these
      // SD-era codecs is cheap. Keep hardware for the modern codecs only.
      await (player.platform as NativePlayer).setProperty('hwdec-codecs', 'h264,hevc,vp8,vp9,av1');
      // Delays and speed were for the previous file; subtitle looks carry over.
      adjust.value = adjust.value.forNewFile();
      await _applyAdjust(adjust.value);
    }
    if (player.state.rate != 1.0) await player.setRate(1.0);
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

  /// mpv's own audio and subtitle track ids ('1', '2'... or 'no'); media_kit reports tracks
  /// mpv picked by itself as 'auto'.
  Future<({String audio, String subtitle})> activeTrackIds() async {
    final native = player.platform as NativePlayer;
    return (audio: await native.getProperty('aid'), subtitle: await native.getProperty('sid'));
  }

  /// Android Auto and other media browsers: music from the downloads and the servers.
  late final CarLibrary car = CarLibrary(
    accounts: AccountStore.load,
    jellyfin: (a) async => JellyfinClient(a, await AccountStore.deviceId()),
    subsonic: SubsonicClient.new,
    downloads: () async {
      await Downloads.instance.init();
      return Downloads.instance.entries.value.where((e) => !e.isVideo && e.state == DownloadState.done).toList();
    },
    downloadedItem: Downloads.instance.toPlayItem,
  );

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) =>
      car.children(parentMediaId);

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final q = car.queueFor(mediaId);
    if (q != null) await start(q.items, q.index);
  }

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) => car.search(query);

  /// "Play ... on Homeplay" by voice.
  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    final q = await car.queueForSearch(query);
    if (q != null) await start(q.items, q.index);
  }

  /// Plays the current video again in [quality], from where it is now. False when the
  /// item cannot change quality.
  Future<bool> changeQuality(VideoQuality quality) async {
    final item = currentItem;
    final again = item?.withQuality;
    if (item == null || again == null) return false;
    final at = player.state.position;
    final index = current.value;
    final replaced = await again(quality);
    // The user may have moved on while the server answered.
    if (!identical(currentItem, item)) return false;
    await start([...items.value]..[index] = replaced, index, startAt: at);
    return true;
  }

  /// Switches audio and remembers the language for the next files.
  Future<void> selectAudio(AudioTrack track) async {
    await player.setAudioTrack(track);
    final language = track.language;
    if (language != null) await _prefs?.setString(_audioLanguageKey, language);
  }

  /// Switches subtitles and remembers the choice ('off' or the language) for the next files.
  Future<void> selectSubtitle(SubtitleTrack track) async {
    await player.setSubtitleTrack(track);
    final choice = track.id == 'no' ? 'off' : track.language;
    if (choice != null) await _prefs?.setString(_subtitleLanguageKey, choice);
  }

  void _applyTrackChoice(Tracks t) {
    final item = currentItem;
    if (item == null || !item.isVideo || _tracksApplied.contains(current.value)) return;
    // The first events come before the file's own tracks are known.
    if (!t.audio.any((a) => a.id != 'auto' && a.id != 'no') && !t.video.any((v) => v.id != 'auto' && v.id != 'no')) {
      return;
    }
    // Subtitle files first, so a remembered language can pick one of them too. Their tracks
    // arrive as another event, which comes back here.
    if (item.subtitles.isNotEmpty && _subtitlesAdded.add(current.value)) {
      _addSubtitles(item);
      return;
    }
    _tracksApplied.add(current.value);
    final selected = player.state.track;
    final audio = chooseAudio(t.audio,
        forcedId: item.audioTrackId, preferredLanguage: _prefs?.getString(_audioLanguageKey));
    if (audio != null && audio.id != selected.audio.id) player.setAudioTrack(audio);
    if (item.audioTrackId != null && item.notice != null && audio?.id == item.audioTrackId) {
      _notices.add(item.notice!);
    }
    final sub = chooseSubtitle(t.subtitle, _prefs?.getString(_subtitleLanguageKey));
    if (sub != null && sub.id != selected.subtitle.id) player.setSubtitleTrack(sub);
  }

  /// Adds [item]'s subtitle files to mpv without selecting them. If no track event follows
  /// (every file failed), the choice is applied anyway after a second.
  Future<void> _addSubtitles(PlayItem item) async {
    final native = player.platform as NativePlayer;
    for (final s in item.subtitles) {
      try {
        await native.command(['sub-add', s.url.toString(), 'auto', s.title ?? 'External', ?s.language]);
      } catch (e) {
        // The URL carries the access token, so only the title goes to the log.
        debugPrint('homeplay subtitle file ${s.title} failed: $e');
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    if (identical(currentItem, item)) _applyTrackChoice(player.state.tracks);
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
    // Android may drop audio_service's own cancel of the notification (see MainActivity);
    // ask again once it has settled, unless something else started playing meanwhile.
    Timer(const Duration(milliseconds: 600), () async {
      if (items.value.isNotEmpty) return;
      try {
        await _channel.invokeMethod('cancelNotification');
      } catch (_) {
        // Started without the activity (Android Auto): the channel is not there.
      }
    });
  }

  static const _channel = MethodChannel('homeplay/playback');

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
    _lastStopReport =
        items.value[index].reporter?.stopped(position, duration: mediaItem.value?.duration) ?? Future.value();
  }

  MediaItem _mediaItem(PlayItem i) => MediaItem(
        id: i.url.toString(),
        title: i.title,
        artist: i.subtitle,
        artUri: i.artwork,
        artHeaders: i.headers.isEmpty ? null : i.headers,
      );

  void _notice() {
    final item = currentItem;
    // A fallback track's notice waits for the track choice: a remembered language may win.
    if (item == null || item.notice == null || item.audioTrackId != null) return;
    _notices.add(item.notice!);
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
    s.tracks.listen(_applyTrackChoice);
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
    // Dropped frames and the frame rate actually shown tell a choking decoder from a slow network.
    final dropped = await native.getProperty('frame-drop-count');
    final decoderDropped = await native.getProperty('decoder-frame-drop-count');
    final fps = await native.getProperty('estimated-display-fps');
    final sourceFps = await native.getProperty('container-fps');
    debugPrint('homeplay cache: ${(speed * 8 / 1e6).toStringAsFixed(1)} Mbit/s, ${ahead}s ahead, '
        'pos=${st.position.inSeconds}s buffering=${st.buffering} playing=${st.playing}; '
        'dropped=$dropped decoderDropped=$decoderDropped fps=$fps/$sourceFps');
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
