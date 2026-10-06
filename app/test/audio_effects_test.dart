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

  test('raised bands become mpv equalizer filters with headroom', () {
    final f = equalizerFilter([6, 0, 0, 0, 0, -3, 0, 0, 0, 0]);
    expect(f, 'lavfi=[equalizer=f=31:t=o:w=1:g=6.0,equalizer=f=1000:t=o:w=1:g=-3.0,volume=volume=-3.0dB]');
    // Only cuts: nothing clips, no volume change.
    expect(equalizerFilter([0, 0, -4, 0, 0, 0, 0, 0, 0, 0]), 'lavfi=[equalizer=f=125:t=o:w=1:g=-4.0]');
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
}
