import 'package:flutter/painting.dart';

/// How the picture fills the screen: the "aspect" button cycles through these.
enum FrameFit {
  fit('Fit', BoxFit.contain, null),
  fill('Fill', BoxFit.cover, null),
  stretch('Stretch', BoxFit.fill, null),
  wide('16:9', BoxFit.contain, 16 / 9),
  classic('4:3', BoxFit.contain, 4 / 3);

  const FrameFit(this.label, this.boxFit, this.aspectRatio);

  final String label;
  final BoxFit boxFit;

  /// Forced picture shape; null keeps the file's own.
  final double? aspectRatio;

  FrameFit get next => values[(index + 1) % values.length];
}

/// Playback speeds offered in the menu.
const playbackSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];

/// "1×", "1.25×", "0.5×".
String speedLabel(double rate) {
  var s = rate.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$s×';
}

/// A level (brightness, volume) from 0 to 1 after a vertical drag of [dy] pixels (down is
/// positive) on a screen [height] tall. Swiping across 70% of the height covers the whole range.
double dragLevel(double start, double dy, double height) {
  if (height <= 0) return start.clamp(0.0, 1.0);
  return (start - dy / (height * 0.7)).clamp(0.0, 1.0);
}

/// Where a horizontal drag of [dx] pixels on a screen [width] wide seeks to from [from].
/// The full width is two minutes, or the whole video when it is shorter.
Duration seekByDrag(Duration from, double dx, double width, Duration total) {
  if (width <= 0) return from;
  final span = total > Duration.zero && total < const Duration(minutes: 2) ? total : const Duration(minutes: 2);
  final ms = from.inMilliseconds + (dx / width * span.inMilliseconds).round();
  final end = total > Duration.zero ? total.inMilliseconds : ms;
  return Duration(milliseconds: ms.clamp(0, end < 0 ? 0 : end));
}

/// "+0:15", "−1:05:00" for a seek preview.
String signedDuration(Duration d) {
  final sign = d.isNegative ? '−' : '+';
  final a = d.abs();
  final h = a.inHours;
  final m = a.inMinutes.remainder(60);
  final s = a.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$sign$h:${m.toString().padLeft(2, '0')}:$s' : '$sign$m:$s';
}

/// "+0.5 s", "−1.2 s", "0 s" for subtitle and audio delays.
String delayLabel(double seconds) {
  final rounded = (seconds * 10).round() / 10;
  if (rounded == 0) return '0 s';
  return '${rounded > 0 ? '+' : '−'}${rounded.abs().toStringAsFixed(1)} s';
}

/// A delay [seconds] moved by [step], kept within ±60 s and free of float noise.
double stepDelay(double seconds, double step) => (((seconds + step) * 10).round() / 10).clamp(-60.0, 60.0);

/// Subtitle and sound adjustments of the video player. Size, position and colour stay for the
/// next videos; delays fit one file and start at zero with each new one.
class VideoAdjust {
  const VideoAdjust({
    this.subtitleDelay = 0,
    this.audioDelay = 0,
    this.subtitleScale = 1,
    this.subtitlePosition = 100,
    this.subtitleYellow = false,
  });

  /// Seconds; positive shows subtitles later.
  final double subtitleDelay;

  /// Seconds; positive plays the sound later.
  final double audioDelay;

  /// 1 is the normal size.
  final double subtitleScale;

  /// mpv's sub-pos: 100 is the bottom of the picture, 0 the top.
  final int subtitlePosition;

  /// Yellow instead of white text (plain subtitles; styled ASS keeps its own colours).
  final bool subtitleYellow;

  static const minScale = 0.5;
  static const maxScale = 2.5;
  static const minPosition = 50;

  VideoAdjust copyWith({
    double? subtitleDelay,
    double? audioDelay,
    double? subtitleScale,
    int? subtitlePosition,
    bool? subtitleYellow,
  }) =>
      VideoAdjust(
        subtitleDelay: subtitleDelay ?? this.subtitleDelay,
        audioDelay: audioDelay ?? this.audioDelay,
        subtitleScale: subtitleScale ?? this.subtitleScale,
        subtitlePosition: subtitlePosition ?? this.subtitlePosition,
        subtitleYellow: subtitleYellow ?? this.subtitleYellow,
      );

  /// For the next file: the kept settings, no delays.
  VideoAdjust forNewFile() => VideoAdjust(
        subtitleScale: subtitleScale,
        subtitlePosition: subtitlePosition,
        subtitleYellow: subtitleYellow,
      );

  /// mpv properties for these settings.
  Map<String, String> get mpvProperties => {
        'sub-delay': subtitleDelay.toString(),
        'audio-delay': audioDelay.toString(),
        'sub-scale': subtitleScale.toStringAsFixed(2),
        'sub-pos': subtitlePosition.toString(),
        'sub-color': subtitleYellow ? '#FFFF00' : '#FFFFFF',
      };

  /// What to save between videos.
  Map<String, Object> toPrefs() => {
        'subtitle_scale': subtitleScale,
        'subtitle_position': subtitlePosition,
        'subtitle_yellow': subtitleYellow,
      };

  static VideoAdjust fromPrefs(Object? Function(String key) read) {
    final scale = read('subtitle_scale');
    final position = read('subtitle_position');
    final yellow = read('subtitle_yellow');
    return VideoAdjust(
      subtitleScale: scale is double ? scale.clamp(minScale, maxScale) : 1,
      subtitlePosition: position is int ? position.clamp(minPosition, 100) : 100,
      subtitleYellow: yellow == true,
    );
  }
}
