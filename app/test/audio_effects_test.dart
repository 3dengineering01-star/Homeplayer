import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/audio_effects.dart';

void main() {
  test('every preset has a gain per band within the limits', () {
    for (final e in eqPresets.entries) {
      expect(e.value.length, eqBands.length, reason: e.key);
      expect(e.value.every((g) => g.abs() <= eqMaxGain), isTrue, reason: e.key);
    }
  });

  test('a flat or switched-off equalizer adds no filter', () {
    expect(equalizerFilter(eqPresets['Flat']!), '');
    expect(SoundSettings(gains: eqPresets['Rock']!).filter, '');
  });

  test('bands become mpv equalizer filters', () {
    final gains = <double>[6, 0, 0, 0, 0, -3, 0, 0, 0, 0];
    expect(equalizerFilter(gains), 'lavfi=[equalizer=f=31:t=o:w=1:g=6.0,equalizer=f=1000:t=o:w=1:g=-3.0]');
  });

  test('the volume goes down by the peak of the curve, so raised bands do not clip', () {
    // One band: the peak is that band.
    final one = <double>[0, 0, 0, 0, 0, 6, 0, 0, 0, 0];
    expect(equalizerPeakDb(one), closeTo(6, 0.3));
    expect(equalizerVolume(one), closeTo(50, 2));
    // Neighbours add up: Bass boost peaks above its highest band (+7).
    expect(equalizerPeakDb(eqPresets['Bass boost']!), greaterThan(7.5));
    // Only cuts, or flat: nothing clips, full volume.
    expect(equalizerVolume([0, 0, -4, 0, 0, 0, 0, 0, 0, 0]), 100);
    expect(equalizerVolume(eqPresets['Flat']!), 100);
    expect(SoundSettings(gains: one).volume, 100, reason: 'switched off');
    expect(SoundSettings(enabled: true, gains: one).volume, closeTo(50, 2));
  });

  test('settings survive a restart and name their preset', () {
    final s = SoundSettings(enabled: true, gains: eqPresets['Bass boost']!, replayGain: ReplayGain.album);
    final saved = s.toPrefs();
    final loaded = SoundSettings.fromPrefs((k) => saved[k]);
    expect(loaded.enabled, isTrue);
    expect(loaded.gains, eqPresets['Bass boost']);
    expect(loaded.replayGain, ReplayGain.album);
    expect(loaded.preset, 'Bass boost');
    expect(loaded.copyWith(gains: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]).preset, isNull);
  });

  test('broken saved settings fall back to a flat, switched-off equalizer', () {
    final s = SoundSettings.fromPrefs((k) => {'eq_gains': '1,2,x', 'replay_gain': 'loud'}[k]);
    expect(s.enabled, isFalse);
    expect(s.gains, const SoundSettings().gains);
    expect(s.replayGain, ReplayGain.off);
  });

  test('band labels', () {
    expect(bandLabel(31), '31');
    expect(bandLabel(16000), '16k');
  });

  test("Android's equalizer bands end between our band centres, the last at 20 kHz", () {
    final c = eqCutoffs();
    expect(c.length, eqBands.length);
    for (var i = 0; i < eqBands.length; i++) {
      expect(c[i], greaterThan(eqBands[i]));
      if (i > 0) expect(c[i - 1], lessThan(eqBands[i]));
    }
    expect(c.first, closeTo(44, 0.5));
    expect(c.last, 20000);
  });
}
