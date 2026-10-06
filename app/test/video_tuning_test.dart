import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/video_tuning.dart';

void main() {
  test('the aspect button cycles through every frame fit and back', () {
    var f = FrameFit.fit;
    final seen = <FrameFit>[];
    for (var i = 0; i < FrameFit.values.length; i++) {
      seen.add(f);
      f = f.next;
    }
    expect(seen, FrameFit.values);
    expect(f, FrameFit.fit);
    expect(FrameFit.fill.boxFit, BoxFit.cover);
    expect(FrameFit.wide.aspectRatio, closeTo(1.778, 0.001));
    expect(FrameFit.fit.aspectRatio, isNull);
  });

  test('speed labels drop trailing zeros', () {
    expect(speedLabel(1), '1×');
    expect(speedLabel(1.25), '1.25×');
    expect(speedLabel(0.5), '0.5×');
    expect(speedLabel(2), '2×');
    expect(speedLabel(10), '10×');
  });

  test('a vertical drag moves the level, up is more, and stays within 0..1', () {
    expect(dragLevel(0.5, 0, 1000), 0.5);
    expect(dragLevel(0.5, -350, 1000), closeTo(1.0, 1e-9));
    expect(dragLevel(0.5, 350, 1000), closeTo(0.0, 1e-9));
    expect(dragLevel(0.5, -2000, 1000), 1.0);
    expect(dragLevel(0.5, 2000, 1000), 0.0);
    expect(dragLevel(0.3, 100, 0), 0.3);
  });

  test('a horizontal drag seeks two minutes per screen width, within the video', () {
    const total = Duration(minutes: 90);
    expect(seekByDrag(const Duration(minutes: 10), 500, 1000, total), const Duration(minutes: 11));
    expect(seekByDrag(const Duration(minutes: 10), -1000, 1000, total), const Duration(minutes: 8));
    expect(seekByDrag(const Duration(seconds: 30), -1000, 1000, total), Duration.zero);
    expect(seekByDrag(const Duration(minutes: 89), 1000, 1000, total), total);
    // A short clip: the full width is the whole clip.
    expect(seekByDrag(Duration.zero, 500, 1000, const Duration(seconds: 40)), const Duration(seconds: 20));
    // Duration not known yet: only the start bounds it.
    expect(seekByDrag(const Duration(seconds: 5), 1000, 1000, Duration.zero), const Duration(seconds: 125));
  });

  test('seek previews and delays carry a sign', () {
    expect(signedDuration(const Duration(seconds: 15)), '+0:15');
    expect(signedDuration(const Duration(seconds: -65)), '−1:05');
    expect(signedDuration(const Duration(hours: 1, seconds: 3)), '+1:00:03');
    expect(delayLabel(0), '0 s');
    expect(delayLabel(0.04), '0 s');
    expect(delayLabel(0.5), '+0.5 s');
    expect(delayLabel(-1.2), '−1.2 s');
  });

  test('delay steps add up without float noise and stop at a minute', () {
    var d = 0.0;
    for (var i = 0; i < 3; i++) {
      d = stepDelay(d, 0.1);
    }
    expect(d, 0.3);
    expect(stepDelay(59.9, 0.5), 60.0);
    expect(stepDelay(-59.9, -0.5), -60.0);
  });

  test('subtitle size, position and colour carry over to the next video, delays do not', () {
    const a = VideoAdjust(subtitleDelay: 1.5, audioDelay: -0.3, subtitleScale: 1.4, subtitlePosition: 80, subtitleYellow: true);
    final next = a.forNewFile();
    expect(next.subtitleDelay, 0);
    expect(next.audioDelay, 0);
    expect(next.subtitleScale, 1.4);
    expect(next.subtitlePosition, 80);
    expect(next.subtitleYellow, isTrue);

    final saved = a.toPrefs();
    final loaded = VideoAdjust.fromPrefs((k) => saved[k]);
    expect(loaded.subtitleScale, 1.4);
    expect(loaded.subtitlePosition, 80);
    expect(loaded.subtitleYellow, isTrue);
    expect(loaded.subtitleDelay, 0);
  });

  test('missing or broken saved subtitle settings fall back to the defaults', () {
    final empty = VideoAdjust.fromPrefs((_) => null);
    expect(empty.subtitleScale, 1);
    expect(empty.subtitlePosition, 100);
    expect(empty.subtitleYellow, isFalse);
    final wild = VideoAdjust.fromPrefs((k) => {'subtitle_scale': 9.0, 'subtitle_position': 3}[k]);
    expect(wild.subtitleScale, VideoAdjust.maxScale);
    expect(wild.subtitlePosition, VideoAdjust.minPosition);
  });

  test('settings become mpv properties', () {
    const a = VideoAdjust(subtitleDelay: -0.5, subtitleScale: 1.25, subtitlePosition: 90, subtitleYellow: true);
    expect(a.mpvProperties, {
      'sub-delay': '-0.5',
      'audio-delay': '0.0',
      'sub-scale': '1.25',
      'sub-pos': '90',
      'sub-color': '#FFFF00',
    });
  });
}
