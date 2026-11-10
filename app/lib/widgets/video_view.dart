import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../api/common.dart';
import '../screens/tv_screen.dart';
import '../services/pip.dart';
import '../services/playback.dart';
import '../services/video_extras.dart';
import '../services/video_tuning.dart';
import 'appearance_picker.dart';
import 'track_sheet.dart';
import 'video_tune_sheet.dart';

enum _Drag { none, brightness, volume, seek, pinch }

/// The video player: the picture full screen with its own controls and gestures.
/// Left side up and down: brightness. Right side: volume. Sideways: seek. Double tap on the
/// sides: 10 seconds back or forward. Two fingers: fill the screen or fit the picture.
class VideoView extends StatefulWidget {
  const VideoView({super.key, required this.pb, required this.item, required this.hasPrev, required this.hasNext});

  final Playback pb;
  final PlayItem item;
  final bool hasPrev;
  final bool hasNext;

  @override
  State<VideoView> createState() => _VideoViewState();
}

/// Kept while the app runs: the next video opens the way the last one was watched.
FrameFit _lastFit = FrameFit.fit;

class _VideoViewState extends State<VideoView> {
  Playback get _pb => widget.pb;

  bool _controls = true;
  bool _locked = false;
  FrameFit _fit = _lastFit;
  Timer? _hideTimer;

  // Gesture in progress.
  _Drag _drag = _Drag.none;
  Offset _dragStart = Offset.zero;
  double _levelStart = 0;
  Duration _seekFrom = Duration.zero;
  Duration? _seekTo;
  double _pinchScale = 1;

  // Brightness and volume as last known; the plugins answer asynchronously.
  double? _brightness;
  bool _brightnessChanged = false;
  double _volume = 0.5;
  StreamSubscription<double>? _volumeSub;

  // Brief feedback in the middle of the screen: what a gesture did.
  // [at]: the time a seek goes to, for its picture when the server has them.
  final ValueNotifier<({IconData icon, String text, double? level, Duration? at})?> _hud = ValueNotifier(null);
  Timer? _hudTimer;

  bool _pipAvailable = false;
  final List<StreamSubscription<dynamic>> _subs = [];

  // The intro, the credits and the pictures for seeking, once the server has answered.
  final ValueNotifier<VideoExtras?> _extras = ValueNotifier(null);
  Object? _extrasRequest;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    VolumeController.instance.showSystemUI = false;
    _volumeSub = VolumeController.instance.addListener((v) => _volume = v);
    _readBrightness();
    Pip.instance.available().then((a) {
      if (mounted) setState(() => _pipAvailable = a);
    });
    final s = _pb.player.stream;
    _subs
      ..add(s.playing.listen((playing) {
        _updateAutoPip();
        if (playing) {
          _scheduleHide();
        } else {
          _show(hideLater: false);
        }
      }))
      ..add(s.width.listen((_) => _updateAutoPip()));
    _updateAutoPip();
    _scheduleHide();
    _loadExtras();
  }

  @override
  void didUpdateWidget(VideoView old) {
    super.didUpdateWidget(old);
    // The same view goes on to the next episode.
    if (old.item.extras != widget.item.extras) _loadExtras();
  }

  void _loadExtras() {
    _extras.value = null;
    final ask = widget.item.extras;
    final request = _extrasRequest = Object();
    if (ask == null) return;
    ask().then((x) {
      // An answer for a video that is no longer on the screen is dropped.
      if (mounted && _extrasRequest == request) _extras.value = x;
    }, onError: (Object e) => debugPrint('homeplay video extras: $e'));
  }

  /// Past [s]: to its end, or to the next video when it is the credits at the very end.
  void _skip(MediaSegment s) {
    final duration = widget.item.duration ?? _pb.player.state.duration;
    if (endsVideo(s, duration) && widget.hasNext) {
      _pb.skipToNext();
    } else {
      _pb.seek(s.end);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _volumeSub?.cancel();
    VolumeController.instance.showSystemUI = true;
    if (_brightnessChanged) ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    Pip.instance.setAuto(false);
    _hud.dispose();
    _extras.dispose();
    super.dispose();
  }

  Future<void> _readBrightness() async {
    try {
      _brightness ??= await ScreenBrightness.instance.application;
    } catch (_) {
      // Unknown: a drag starts from the middle.
    }
  }

  /// Leaving the app while a video plays shrinks it to a small window.
  void _updateAutoPip() {
    final st = _pb.player.state;
    Pip.instance.setAuto(st.playing, width: st.width, height: st.height);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _pb.player.state.playing) setState(() => _controls = false);
    });
  }

  void _show({bool hideLater = true}) {
    if (!mounted) return;
    if (!_controls) setState(() => _controls = true);
    if (hideLater) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _toggleControls() {
    if (_controls) {
      _hideTimer?.cancel();
      setState(() => _controls = false);
    } else {
      _show(hideLater: _pb.player.state.playing);
    }
  }

  void _flash(IconData icon, String text, {double? level, Duration? at, bool stay = false}) {
    _hudTimer?.cancel();
    _hud.value = (icon: icon, text: text, level: level, at: at);
    if (!stay) _hudTimer = Timer(const Duration(milliseconds: 800), () => _hud.value = null);
  }

  void _endFlash() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 600), () => _hud.value = null);
  }

  Future<void> _seekBy(Duration d) async {
    final st = _pb.player.state;
    var to = st.position + d;
    if (to < Duration.zero) to = Duration.zero;
    if (st.duration > Duration.zero && to > st.duration) to = st.duration;
    await _pb.seek(to);
  }

  void _setFit(FrameFit f) {
    setState(() => _fit = _lastFit = f);
    _flash(Icons.aspect_ratio, f.label);
  }

  void _rotate() {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setPreferredOrientations(landscape
        ? const [DeviceOrientation.portraitUp]
        : const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  Future<void> _enterPip() async {
    final st = _pb.player.state;
    setState(() => _controls = false);
    await Pip.instance.enter(width: st.width, height: st.height);
  }

  // --- Gestures ---

  void _onDoubleTap(TapDownDetails d, Size size) {
    if (_locked) return;
    final x = d.localPosition.dx;
    if (x < size.width / 3) {
      _seekBy(const Duration(seconds: -10));
      _flash(Icons.replay_10, '−10 s');
    } else if (x > size.width * 2 / 3) {
      _seekBy(const Duration(seconds: 10));
      _flash(Icons.forward_10, '+10 s');
    } else {
      final playing = _pb.player.state.playing;
      playing ? _pb.pause() : _pb.play();
      _flash(playing ? Icons.pause : Icons.play_arrow, playing ? 'Paused' : 'Play');
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _drag = d.pointerCount >= 2 ? _Drag.pinch : _Drag.none;
    _dragStart = d.localFocalPoint;
    _pinchScale = 1;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    if (_locked) return;
    if (d.pointerCount >= 2 && _drag != _Drag.seek) {
      _drag = _Drag.pinch;
      _pinchScale = d.scale;
      return;
    }
    if (_drag == _Drag.pinch) return;
    final delta = d.localFocalPoint - _dragStart;
    if (_drag == _Drag.none) {
      // The system takes swipes from the very top and bottom edges.
      if (_dragStart.dy < 32 || _dragStart.dy > size.height - 32) return;
      if (delta.distance < 16) return;
      if (delta.dx.abs() > delta.dy.abs()) {
        final st = _pb.player.state;
        if (st.duration <= Duration.zero) return;
        _drag = _Drag.seek;
        _seekFrom = st.position;
      } else if (_dragStart.dx < size.width / 2) {
        _drag = _Drag.brightness;
        _levelStart = _brightness ?? 0.5;
      } else {
        _drag = _Drag.volume;
        _levelStart = _volume;
      }
    }
    switch (_drag) {
      case _Drag.seek:
        final total = _pb.player.state.duration;
        final to = _seekTo = seekByDrag(_seekFrom, delta.dx, size.width, total);
        _flash(to >= _seekFrom ? Icons.fast_forward : Icons.fast_rewind,
            '${formatDuration(to)}  (${signedDuration(to - _seekFrom)})', at: to, stay: true);
      case _Drag.brightness:
        final b = _brightness = dragLevel(_levelStart, delta.dy, size.height);
        _brightnessChanged = true;
        ScreenBrightness.instance.setApplicationScreenBrightness(b).catchError((_) {});
        _flash(Icons.brightness_6, 'Brightness', level: b, stay: true);
      case _Drag.volume:
        final v = _volume = dragLevel(_levelStart, delta.dy, size.height);
        VolumeController.instance.setVolume(v).catchError((_) {});
        _flash(v == 0 ? Icons.volume_off : Icons.volume_up, 'Volume', level: v, stay: true);
      case _Drag.none:
      case _Drag.pinch:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    switch (_drag) {
      case _Drag.pinch:
        if (_pinchScale > 1.15 && _fit != FrameFit.fill) _setFit(FrameFit.fill);
        if (_pinchScale < 0.87 && _fit != FrameFit.fit) _setFit(FrameFit.fit);
      case _Drag.seek:
        final to = _seekTo;
        if (to != null) _pb.seek(to);
        _endFlash();
      case _Drag.brightness:
      case _Drag.volume:
        _endFlash();
      case _Drag.none:
        break;
    }
    _drag = _Drag.none;
    _seekTo = null;
  }

  // --- Building ---

  @override
  Widget build(BuildContext context) {
    final video = Video(
      controller: _pb.video,
      controls: NoVideoControls,
      fit: _fit.boxFit,
      aspectRatio: _fit.aspectRatio,
      // Subtitles are drawn by libass into the video, not by Flutter on top of it.
      subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: Pip.instance.active,
      builder: (context, inPip, _) {
        // Locked: back does nothing either, as in a pocket.
        return PopScope(
          canPop: !_locked,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _show();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: LayoutBuilder(builder: (context, box) {
              final size = box.biggest;
              final visible = _controls ? 1.0 : 0.0;
              const fade = Duration(milliseconds: 200);
              // The small window has no room for controls; Android puts its own on it. The
              // picture stays where it is in the tree, so it goes on without a blink.
              if (inPip) return Stack(fit: StackFit.expand, children: [video]);
              return Stack(fit: StackFit.expand, children: [
                video,
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _locked ? () => _show() : _toggleControls,
                  onDoubleTapDown: (d) => _onDoubleTap(d, size),
                  onDoubleTap: () {},
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: (d) => _onScaleUpdate(d, size),
                  onScaleEnd: _onScaleEnd,
                ),
                // Shade behind the controls so they read on a bright picture; taps go through.
                if (!_locked)
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: visible,
                      duration: fade,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xAA000000), Colors.transparent, Colors.transparent, Color(0xAA000000)],
                            stops: [0, 0.25, 0.65, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                _Buffering(pb: _pb),
                _Hud(hud: _hud, extras: _extras, headers: widget.item.headers),
                IgnorePointer(
                  ignoring: !_controls,
                  child: AnimatedOpacity(
                    opacity: visible,
                    duration: fade,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) => _show(hideLater: _pb.player.state.playing),
                      child: _locked ? _lockedControls() : _fullControls(context),
                    ),
                  ),
                ),
                // Over everything and also with the controls hidden, as on TV apps.
                if (!_locked) _SkipButton(pb: _pb, extras: _extras, onSkip: _skip),
              ]);
            }),
          ),
        );
      },
    );
  }

  Widget _lockedControls() => SafeArea(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: IconButton.filledTonal(
              tooltip: 'Unlock',
              iconSize: 28,
              onPressed: () {
                setState(() => _locked = false);
                _show();
              },
              icon: const Icon(Icons.lock),
            ),
          ),
        ),
      );

  Widget _fullControls(BuildContext context) => SafeArea(
        child: IconTheme(
          data: const IconThemeData(color: Colors.white),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(children: [
              _topBar(context),
              Expanded(child: Center(child: _transport())),
              _SeekRow(pb: _pb, extras: _extras, headers: widget.item.headers),
              _bottomBar(context),
            ]),
          ),
        ),
      );

  Widget _topBar(BuildContext context) => Row(children: [
        IconButton(
          tooltip: 'Back',
          color: Colors.white,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(widget.item.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
            if (widget.item.subtitle != null)
              Text(widget.item.subtitle!,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        IconButton(
          tooltip: 'Play on TV',
          color: Colors.white,
          onPressed: () {
            _hideTimer?.cancel();
            // The TV goes on from here. The remote takes the player's place, and closing the
            // player ends the phone's own playback.
            playOnTv(context, widget.item, startAt: _pb.player.state.position, replace: true);
          },
          icon: const Icon(Icons.cast),
        ),
        IconButton(
          tooltip: 'Audio, subtitles and quality',
          color: Colors.white,
          onPressed: () {
            _hideTimer?.cancel();
            showTrackSheet(context, _pb);
          },
          icon: const Icon(Icons.subtitles_outlined),
        ),
        IconButton(
          tooltip: 'Speed, subtitle size and delays',
          color: Colors.white,
          onPressed: () {
            _hideTimer?.cancel();
            showVideoTuneSheet(context, _pb);
          },
          icon: const Icon(Icons.tune),
        ),
        IconButton(
          tooltip: 'Appearance',
          color: Colors.white,
          onPressed: () {
            _hideTimer?.cancel();
            showAppearanceSheet(context);
          },
          icon: const Icon(Icons.palette_outlined),
        ),
      ]);

  Widget _transport() => Row(mainAxisSize: MainAxisSize.min, children: [
        if (widget.hasPrev)
          IconButton(
            tooltip: 'Previous',
            color: Colors.white,
            iconSize: 36,
            onPressed: _pb.skipToPrevious,
            icon: const Icon(Icons.skip_previous),
          ),
        IconButton(
          tooltip: '10 seconds back',
          color: Colors.white,
          iconSize: 40,
          onPressed: () => _seekBy(const Duration(seconds: -10)),
          icon: const Icon(Icons.replay_10),
        ),
        const SizedBox(width: 12),
        StreamBuilder<bool>(
          stream: _pb.player.stream.playing,
          initialData: _pb.player.state.playing,
          builder: (context, s) => IconButton(
            tooltip: s.data! ? 'Pause' : 'Play',
            color: Colors.white,
            iconSize: 64,
            onPressed: s.data! ? _pb.pause : _pb.play,
            icon: Icon(s.data! ? Icons.pause_circle_filled : Icons.play_circle_filled),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: '10 seconds forward',
          color: Colors.white,
          iconSize: 40,
          onPressed: () => _seekBy(const Duration(seconds: 10)),
          icon: const Icon(Icons.forward_10),
        ),
        if (widget.hasNext)
          IconButton(
            tooltip: 'Next',
            color: Colors.white,
            iconSize: 36,
            onPressed: _pb.skipToNext,
            icon: const Icon(Icons.skip_next),
          ),
      ]);

  Widget _bottomBar(BuildContext context) {
    Widget button(String tooltip, IconData icon, VoidCallback onPressed) =>
        IconButton(tooltip: tooltip, color: Colors.white, onPressed: onPressed, icon: Icon(icon));
    return Row(children: [
      button('Lock the screen', Icons.lock_open, () {
        setState(() => _locked = true);
        _flash(Icons.lock, 'Locked');
        _scheduleHide();
      }),
      const Spacer(),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        onPressed: () => _setFit(_fit.next),
        icon: const Icon(Icons.aspect_ratio),
        label: Text(_fit.label),
      ),
      StreamBuilder<double>(
        stream: _pb.player.stream.rate,
        initialData: _pb.player.state.rate,
        builder: (context, rate) => PopupMenuButton<double>(
          tooltip: 'Speed',
          initialValue: rate.data,
          onOpened: () => _hideTimer?.cancel(),
          onSelected: (s) {
            _pb.player.setRate(s);
            _scheduleHide();
          },
          itemBuilder: (_) => [for (final s in playbackSpeeds) PopupMenuItem(value: s, child: Text(speedLabel(s)))],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.speed, color: Colors.white),
              const SizedBox(width: 8),
              Text(speedLabel(rate.data!), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      ),
      button('Rotate', Icons.screen_rotation, _rotate),
      if (_pipAvailable) button('Picture in picture', Icons.picture_in_picture_alt, _enterPip),
    ]);
  }
}

class _SeekRow extends StatefulWidget {
  const _SeekRow({required this.pb, required this.extras, required this.headers});
  final Playback pb;
  final ValueListenable<VideoExtras?> extras;
  final Map<String, String> headers;

  @override
  State<_SeekRow> createState() => _SeekRowState();
}

class _SeekRowState extends State<_SeekRow> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final p = widget.pb.player;
    return StreamBuilder<Duration>(
      stream: p.stream.duration,
      initialData: p.state.duration,
      builder: (context, dur) => StreamBuilder<Duration>(
        stream: p.stream.position,
        initialData: p.state.position,
        builder: (context, pos) {
          final total = dur.data!.inMilliseconds.toDouble();
          final current = (_dragging ?? pos.data!.inMilliseconds.toDouble()).clamp(0.0, total > 0 ? total : 0.0);
          final buffered = p.state.buffer.inMilliseconds.toDouble().clamp(0.0, total > 0 ? total : 0.0);
          final row = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text(formatDuration(Duration(milliseconds: current.round())), style: const TextStyle(color: Colors.white)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    thumbColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    secondaryActiveTrackColor: Colors.white54,
                    overlayColor: Colors.white24,
                  ),
                  child: Slider(
                    value: current,
                    secondaryTrackValue: buffered,
                    max: total > 0 ? total : 1,
                    onChanged: total > 0 ? (v) => setState(() => _dragging = v) : null,
                    onChangeEnd: (v) {
                      widget.pb.seek(Duration(milliseconds: v.round()));
                      setState(() => _dragging = null);
                    },
                  ),
                ),
              ),
              Text(formatDuration(dur.data!), style: const TextStyle(color: Colors.white)),
            ]),
          );
          final extras = widget.extras.value;
          final dragging = _dragging;
          if (dragging == null || extras == null || !extras.canPreview || total <= 0) return row;
          // The picture above the finger, kept inside the screen.
          return LayoutBuilder(builder: (context, box) {
            const width = 176.0;
            final x = (box.maxWidth * dragging / total - width / 2).clamp(8.0, math.max(8.0, box.maxWidth - width - 8)).toDouble();
            return Stack(clipBehavior: Clip.none, children: [
              row,
              Positioned(
                left: x,
                bottom: 52,
                child: TrickplayTile(
                    extras: extras, at: Duration(milliseconds: dragging.round()), headers: widget.headers, width: width),
              ),
            ]);
          });
        },
      ),
    );
  }
}

class _Buffering extends StatelessWidget {
  const _Buffering({required this.pb});
  final Playback pb;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: StreamBuilder<bool>(
          stream: pb.player.stream.buffering,
          initialData: pb.player.state.buffering,
          builder: (context, b) =>
              b.data! ? const Center(child: CircularProgressIndicator(color: Colors.white)) : const SizedBox.shrink(),
        ),
      );
}

class _Hud extends StatelessWidget {
  const _Hud({required this.hud, required this.extras, required this.headers});
  final ValueNotifier<({IconData icon, String text, double? level, Duration? at})?> hud;
  final ValueListenable<VideoExtras?> extras;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ValueListenableBuilder(
          valueListenable: hud,
          builder: (context, h, _) => AnimatedOpacity(
            opacity: h == null ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: h == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: const Alignment(0, -0.45),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(12)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (h.at != null && (extras.value?.canPreview ?? false))
                          TrickplayTile(extras: extras.value!, at: h.at!, headers: headers, width: 200)
                        else
                          Icon(h.icon, color: Colors.white, size: 32),
                        const SizedBox(height: 6),
                        Text(h.text, style: const TextStyle(color: Colors.white, fontSize: 16)),
                        if (h.level != null) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 140,
                            child: LinearProgressIndicator(
                              value: h.level,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
          ),
        ),
      );
}

/// "Skip intro" and the like while such a part plays, from what the server knows of the video.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.pb, required this.extras, required this.onSkip});
  final Playback pb;
  final ValueListenable<VideoExtras?> extras;
  final void Function(MediaSegment) onSkip;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoExtras?>(
        valueListenable: extras,
        builder: (context, x, _) {
          final segments = x?.segments ?? const <MediaSegment>[];
          if (segments.isEmpty) return const SizedBox.shrink();
          return StreamBuilder<Duration>(
            stream: pb.player.stream.position,
            initialData: pb.player.state.position,
            builder: (context, pos) {
              final s = skippableAt(segments, pos.data!);
              if (s == null) return const SizedBox.shrink();
              return SafeArea(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24, bottom: 104),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xE6FFFFFF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                      onPressed: () => onSkip(s),
                      icon: const Icon(Icons.skip_next),
                      label: Text(s.kind.label),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
}

/// The server's picture of the video at [at], [width] wide. The server keeps them in sheets of
/// many pictures; the sheet is loaded once and only the right part of it is shown.
class TrickplayTile extends StatelessWidget {
  const TrickplayTile({super.key, required this.extras, required this.at, required this.headers, this.width = 176});

  final VideoExtras extras;
  final Duration at;
  final Map<String, String> headers;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = extras.trickplay!;
    final tile = t.tileAt(at);
    // Decoded no larger than it is shown: a whole sheet at full size is tens of megabytes.
    final tileWidth = math.min(t.width, (width * MediaQuery.devicePixelRatioOf(context)).ceil());
    final tileHeight = t.height * tileWidth / t.width;
    final sheet = ResizeImage(
      NetworkImage(extras.sheetUrl!(tile.sheet).toString(), headers: headers),
      width: t.columns * tileWidth,
      allowUpscaling: false,
    );
    return Container(
      width: width,
      height: width * t.height / t.width,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white70),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: tileWidth.toDouble(),
          height: tileHeight,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform.translate(
                offset: Offset(-tile.column * tileWidth.toDouble(), -tile.row * tileHeight),
                child: Image(
                  image: sheet,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, e, _) {
                    debugPrint('homeplay trickplay sheet ${tile.sheet}: $e');
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
