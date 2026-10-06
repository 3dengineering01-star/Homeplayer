import 'dart:async';
import 'dart:math';

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
import 'audio_effects.dart';
import 'car_library.dart';
import 'downloads.dart';
import 'quality.dart';
import 'queue_edit.dart';
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
    instance.sound.value = SoundSettings.fromPrefs(prefs.get);
    instance.shuffle.value = prefs.getBool(_shuffleKey) ?? false;
    instance.repeat.value = Repeat.values.firstWhere((r) => r.name == prefs.getString(_repeatKey), orElse: () => Repeat.off);
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

  // --- Music: shuffle, repeat, speed, sound, sleep timer ---

  static const _shuffleKey = 'shuffle';
  static const _repeatKey = 'repeat';
  static const _musicRateKey = 'music_rate';

  /// Music plays in random order. The queue itself is reordered, so it shows what comes next.
  final ValueNotifier<bool> shuffle = ValueNotifier(false);

  final ValueNotifier<Repeat> repeat = ValueNotifier(Repeat.off);

  /// Equalizer and volume levelling for music.
  final ValueNotifier<SoundSettings> sound = ValueNotifier(const SoundSettings());

  /// False once mpv has refused the equalizer filter (a libmpv built without it).
  final ValueNotifier<bool> equalizerWorks = ValueNotifier(true);

  /// When the sleep timer pauses the music; null when it is off.
  final ValueNotifier<DateTime?> sleepAt = ValueNotifier(null);

  /// The sleep timer pauses at the end of the current track.
  final ValueNotifier<bool> sleepAfterTrack = ValueNotifier(false);
  Timer? _sleepTimer;

  // The queue in the order it had before shuffling, to go back to it.
  List<PlayItem> _unshuffledOrder = const [];
  final _random = Random();

  bool get _isMusic => !(currentItem?.isVideo ?? false);

  Future<void> setShuffle(bool on) async {
    if (shuffle.value == on) return;
    shuffle.value = on;
    await _prefs?.setBool(_shuffleKey, on);
    _broadcast();
    final list = items.value;
    if (list.length < 2 || !_isMusic) return;
    if (on) {
      _unshuffledOrder = list;
      final order = shuffledOrder(list.length, current.value, _random);
      await _reorder([for (final i in order) list[i]]);
    } else {
      await _reorder(unshuffled(list, _unshuffledOrder));
    }
  }

  Future<void> setRepeat(Repeat r) async {
    repeat.value = r;
    await _prefs?.setString(_repeatKey, r.name);
    if (_isMusic) await player.setPlaylistMode(r.mode);
    _broadcast();
  }

  /// Plays faster or slower; for music the speed is kept for the next queues too.
  @override
  Future<void> setSpeed(double rate) async {
    await player.setRate(rate);
    if (_isMusic) await _prefs?.setDouble(_musicRateKey, rate);
    _broadcast();
  }

  /// Applies the equalizer and volume levelling, and keeps them for the next time.
  Future<void> setSound(SoundSettings settings) async {
    sound.value = settings;
    final prefs = _prefs;
    if (prefs != null) {
      for (final e in settings.toPrefs().entries) {
        switch (e.value) {
          case final bool v:
            await prefs.setBool(e.key, v);
          case final String v:
            await prefs.setString(e.key, v);
        }
      }
    }
    if (_isMusic && items.value.isNotEmpty) await _applySound();
  }

  /// Sets mpv's audio filters for music, none for video.
  Future<void> _applySound() async {
    final native = player.platform as NativePlayer;
    final s = sound.value;
    final filter = _isMusic ? s.filter : '';
    await native.setProperty('replaygain', _isMusic ? s.replayGain.mpv : 'no');
    await native.setProperty('af', filter);
    if (filter.isEmpty) return;
    // mpv keeps the old chain when it can't build the new one, without an error to the caller.
    final now = await native.getProperty('af');
    final works = now.isNotEmpty;
    if (!works) debugPrint('homeplay equalizer refused by mpv');
    equalizerWorks.value = works;
  }

  /// Pauses the music after [after], or at the end of the current track; null turns it off.
  void setSleepTimer(Duration? after, {bool endOfTrack = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAfterTrack.value = endOfTrack;
    sleepAt.value = after == null ? null : DateTime.now().add(after);
    if (after != null) _sleepTimer = Timer(after, _sleepNow);
  }

  void _sleepNow() {
    setSleepTimer(null);
    pause();
  }

  // --- Queue editing ---

  // While above zero, playlist events come from our own edits, not from a track change.
  int _editing = 0;

  /// Moves the queue entry at [from] to [to] (its final position). The playing one keeps playing.
  /// The queue changes at once (lists follow it without a flicker); mpv follows.
  Future<void> moveQueueItem(int from, int to) async {
    if (from == to || from < 0 || to < 0 || from >= items.value.length || to >= items.value.length) return;
    _editing++;
    _remapIndexes((i) => indexAfterMove(i, from, to));
    items.value = moved(items.value, from, to);
    queue.add([for (final i in items.value) _mediaItem(i)]);
    try {
      await player.move(from, mpvMoveTarget(from, to));
      await Future<void>.delayed(Duration.zero);
    } finally {
      _editing--;
    }
    _broadcast();
  }

  /// Takes the entry at [index] out of the queue; not the one playing.
  Future<void> removeFromQueue(int index) async {
    if (index == current.value || index < 0 || index >= items.value.length) return;
    _editing++;
    _remapIndexes((i) => indexAfterRemove(i, index));
    items.value = [...items.value]..removeAt(index);
    queue.add([for (final i in items.value) _mediaItem(i)]);
    try {
      await player.remove(index);
      await Future<void>.delayed(Duration.zero);
    } finally {
      _editing--;
    }
    _broadcast();
  }

  /// Puts [more] right after the playing entry, or plays them when nothing is playing.
  Future<void> playNext(List<PlayItem> more) => _insert(more, next: true);

  /// Puts [more] at the end of the queue, or plays them when nothing is playing.
  Future<void> addToQueue(List<PlayItem> more) => _insert(more, next: false);

  Future<void> _insert(List<PlayItem> more, {required bool next}) async {
    if (more.isEmpty) return;
    if (items.value.isEmpty || !_isMusic || more.any((i) => i.isVideo)) {
      await start(more, 0);
      return;
    }
    _unshuffledOrder = [..._unshuffledOrder, ...more];
    for (final item in more) {
      _editing++;
      try {
        await player.add(Media(item.url.toString(), httpHeaders: item.headers));
        await Future<void>.delayed(Duration.zero);
      } finally {
        _editing--;
      }
      items.value = [...items.value, item];
    }
    if (next) {
      final at = current.value + 1;
      final first = items.value.length - more.length;
      for (var n = 0; n < more.length; n++) {
        await moveQueueItem(first + n, at + n);
      }
    }
    queue.add([for (final i in items.value) _mediaItem(i)]);
    _broadcast();
  }

  /// Puts the queue in [target] order (the same entries) with mpv moves, without a pause.
  Future<void> _reorder(List<PlayItem> target) async {
    for (final (from, to) in movesBetween(items.value, target)) {
      await moveQueueItem(from, to);
    }
  }

  /// Keeps the per-entry bookkeeping on the same entries after an edit.
  void _remapIndexes(int? Function(int) after) {
    Set<int> remap(Set<int> s) => {for (final i in s) ?after(i)};
    final reported = remap(_stopReported);
    final applied = remap(_tracksApplied);
    final added = remap(_subtitlesAdded);
    _stopReported
      ..clear()
      ..addAll(reported);
    _tracksApplied
      ..clear()
      ..addAll(applied);
    _subtitlesAdded
      ..clear()
      ..addAll(added);
    current.value = after(current.value) ?? current.value;
  }

  /// Plays [queueItems] from [index], optionally from [startAt] (a resume point).
  Future<void> start(List<PlayItem> queueItems, int index, {Duration? startAt}) async {
    _endReport(current.value, player.state.position);
    _tracksApplied.clear();
    _subtitlesAdded.clear();
    _stopReported.clear();
    final music = !queueItems.any((i) => i.isVideo);
    _unshuffledOrder = queueItems;
    if (music && shuffle.value && queueItems.length > 1) {
      queueItems = [for (final i in shuffledOrder(queueItems.length, index, _random)) queueItems[i]];
      index = 0;
    }
    items.value = queueItems;
    current.value = index;
    await _applySound();
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
    final rate = music ? (_prefs?.getDouble(_musicRateKey) ?? 1.0) : 1.0;
    if (player.state.rate != rate) await player.setRate(rate);
    await player.setPlaylistMode(music ? repeat.value.mode : PlaylistMode.none);
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
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      setShuffle(shuffleMode != AudioServiceShuffleMode.none);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) => setRepeat(switch (repeatMode) {
        AudioServiceRepeatMode.one => Repeat.one,
        AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => Repeat.all,
        AudioServiceRepeatMode.none => Repeat.off,
      });

  @override
  Future<void> removeQueueItemAt(int index) => removeFromQueue(index);

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
    setSleepTimer(null);
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
      if (_editing > 0) return;
      if (items.value.isEmpty || p.index < 0 || p.index >= items.value.length || p.index == current.value) return;
      if (sleepAfterTrack.value) _sleepNow();
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
      if (done && sleepAfterTrack.value) setSleepTimer(null);
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
      repeatMode: repeat.value.serviceMode,
      shuffleMode: shuffle.value ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
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

/// What plays again: nothing, the whole queue, or the current track.
enum Repeat {
  off(PlaylistMode.none, AudioServiceRepeatMode.none),
  all(PlaylistMode.loop, AudioServiceRepeatMode.all),
  one(PlaylistMode.single, AudioServiceRepeatMode.one);

  const Repeat(this.mode, this.serviceMode);

  final PlaylistMode mode;
  final AudioServiceRepeatMode serviceMode;

  Repeat get next => values[(index + 1) % values.length];
}
