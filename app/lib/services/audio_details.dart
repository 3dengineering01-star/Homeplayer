/// What the music player shows under the seek bar about the sound of the file playing:
/// "FLAC · 24-bit · 96 kHz", "MP3 · 320 kbps · 44.1 kHz". Built from mpv's properties:
/// [codec] (audio-codec-name), [sampleRate] in Hz, [format] (audio-params/format, the decoded
/// sample format) and [bitrate] in bit/s (audio-bitrate). Null when mpv knows nothing yet.
String? audioDetails({String? codec, int? sampleRate, String? format, int? bitrate}) {
  final c = codec?.trim().toLowerCase() ?? '';
  if (c.isEmpty) return null;
  final lossless = _lossless.contains(c) || c.startsWith('pcm_');
  final bits = lossless ? _bits(c, format) : null;
  return [
    _name(c),
    if (bits != null) '$bits-bit',
    if (!lossless && bitrate != null && bitrate > 0) '${(bitrate / 1000).round()} kbps',
    if (sampleRate != null && sampleRate > 0) _kHz(sampleRate),
  ].join(' · ');
}

const _lossless = {'flac', 'alac', 'wavpack', 'ape', 'tta', 'truehd', 'mlp'};

String _name(String codec) => switch (codec) {
      'mp3' || 'mp3float' => 'MP3',
      'aac' || 'aac_fixed' => 'AAC',
      'flac' => 'FLAC',
      'alac' => 'ALAC',
      'opus' => 'Opus',
      'vorbis' => 'Vorbis',
      'wavpack' => 'WavPack',
      'ape' => "Monkey's Audio",
      'ac3' => 'AC3',
      'eac3' => 'E-AC3',
      'dts' => 'DTS',
      'truehd' => 'TrueHD',
      _ when codec.startsWith('pcm_') => 'PCM',
      _ => codec.toUpperCase(),
    };

/// Bit depth of a lossless file. PCM names it (pcm_s24le); FLAC and ALAC decode 24-bit files
/// to 32-bit samples, so s32 there means 24.
int? _bits(String codec, String? format) {
  final pcm = RegExp(r'^pcm_[suf](\d+)').firstMatch(codec);
  if (pcm != null) return int.parse(pcm.group(1)!);
  return switch (format?.replaceAll('p', '')) {
    'u8' => 8,
    's16' => 16,
    's32' => 24,
    _ => null,
  };
}

String _kHz(int hz) {
  final k = hz / 1000;
  return '${k == k.roundToDouble() ? k.round() : k.toStringAsFixed(1)} kHz';
}
