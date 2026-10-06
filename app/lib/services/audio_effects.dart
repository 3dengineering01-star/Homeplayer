/// Equalizer bands in Hz, an octave apart.
const eqBands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/// Band gains are kept within this many dB either way.
const eqMaxGain = 12.0;

/// "31", "1k", "16k" for the band sliders.
String bandLabel(int hz) => hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';

/// Ready-made equalizer curves, one gain per band.
const eqPresets = <String, List<double>>{
  'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Bass boost': [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
  'Bass and treble': [6, 5, 3, 1, 0, 0, 1, 3, 5, 6],
  'Treble boost': [0, 0, 0, 0, 0, 1, 2, 4, 5, 6],
  'Vocal': [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1],
  'Rock': [5, 4, 2, 0, -1, 0, 2, 3, 4, 4],
  'Pop': [-1, 1, 3, 4, 3, 0, -1, -1, 0, 1],
  'Jazz': [3, 2, 1, 2, -1, -1, 0, 1, 2, 3],
  'Classical': [4, 3, 2, 1, 0, 0, 0, 1, 2, 3],
  'Electronic': [5, 4, 1, 0, -2, 1, 0, 1, 4, 5],
};

/// Volume levelling from the files' ReplayGain tags.
enum ReplayGain {
  off('Off', 'no'),
  track('Track', 'track'),
  album('Album', 'album');

  const ReplayGain(this.label, this.mpv);

  final String label;
  final String mpv;
}

/// The music sound settings: equalizer and volume levelling.
class SoundSettings {
  const SoundSettings({this.enabled = false, this.gains = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], this.replayGain = ReplayGain.off});

  final bool enabled;

  /// dB per band of [eqBands].
  final List<double> gains;

  final ReplayGain replayGain;

  SoundSettings copyWith({bool? enabled, List<double>? gains, ReplayGain? replayGain}) => SoundSettings(
        enabled: enabled ?? this.enabled,
        gains: gains ?? this.gains,
        replayGain: replayGain ?? this.replayGain,
      );

  /// The preset these gains match, if any.
  String? get preset {
    for (final e in eqPresets.entries) {
      if (_same(e.value, gains)) return e.key;
    }
    return null;
  }

  /// mpv's audio filter chain: empty when the equalizer is off or flat.
  String get filter => enabled ? equalizerFilter(gains) : '';

  Map<String, Object> toPrefs() => {
        'eq_enabled': enabled,
        'eq_gains': gains.map((g) => g.toString()).join(','),
        'replay_gain': replayGain.name,
      };

  static SoundSettings fromPrefs(Object? Function(String key) read) {
    final raw = read('eq_gains');
    var gains = const SoundSettings().gains;
    if (raw is String) {
      final parsed = raw.split(',').map(double.tryParse).toList();
      if (parsed.length == eqBands.length && parsed.every((g) => g != null)) {
        gains = [for (final g in parsed) g!.clamp(-eqMaxGain, eqMaxGain)];
      }
    }
    final rg = read('replay_gain');
    return SoundSettings(
      enabled: read('eq_enabled') == true,
      gains: gains,
      replayGain: ReplayGain.values.firstWhere((r) => r.name == rg, orElse: () => ReplayGain.off),
    );
  }
}

bool _same(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 0.05) return false;
  }
  return true;
}

/// An mpv audio filter (libavfilter graph) with one peaking band per non-zero gain. Raised bands
/// would clip at full volume, so the whole sound goes down by half the highest raise.
String equalizerFilter(List<double> gains) {
  final bands = <String>[];
  var highest = 0.0;
  for (var i = 0; i < gains.length && i < eqBands.length; i++) {
    final g = gains[i].clamp(-eqMaxGain, eqMaxGain);
    if (g.abs() < 0.05) continue;
    if (g > highest) highest = g;
    bands.add('equalizer=f=${eqBands[i]}:t=o:w=1:g=${_db(g)}');
  }
  if (bands.isEmpty) return '';
  // Named: a bare value starting with '-' reads as an option name to libavfilter.
  if (highest > 0) bands.add('volume=volume=${_db(-highest / 2)}dB');
  return 'lavfi=[${bands.join(',')}]';
}

String _db(double v) => v.toStringAsFixed(1);
