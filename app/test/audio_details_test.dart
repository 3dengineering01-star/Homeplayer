import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/audio_details.dart';

void main() {
  test('lossless shows bit depth and sample rate', () {
    expect(audioDetails(codec: 'flac', sampleRate: 96000, format: 's32', bitrate: 2800000), 'FLAC · 24-bit · 96 kHz');
    expect(audioDetails(codec: 'flac', sampleRate: 44100, format: 's16'), 'FLAC · 16-bit · 44.1 kHz');
    expect(audioDetails(codec: 'alac', sampleRate: 48000, format: 's32p'), 'ALAC · 24-bit · 48 kHz');
    expect(audioDetails(codec: 'pcm_s24le', sampleRate: 192000, format: 's32'), 'PCM · 24-bit · 192 kHz');
  });

  test('lossy shows the bitrate instead', () {
    expect(audioDetails(codec: 'mp3float', sampleRate: 44100, format: 'floatp', bitrate: 320000), 'MP3 · 320 kbps · 44.1 kHz');
    expect(audioDetails(codec: 'aac', sampleRate: 48000, bitrate: 255800), 'AAC · 256 kbps · 48 kHz');
    expect(audioDetails(codec: 'opus', sampleRate: 48000), 'Opus · 48 kHz');
  });

  test('nothing known, nothing shown', () {
    expect(audioDetails(), isNull);
    expect(audioDetails(codec: ' '), isNull);
  });
}
