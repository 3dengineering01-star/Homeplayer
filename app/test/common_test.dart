import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('adds http and strips trailing slashes', () {
      expect(normalizeBaseUrl(' 192.168.1.10:8096/ '), 'http://192.168.1.10:8096');
      expect(normalizeBaseUrl('https://media.example.com/jellyfin//'), 'https://media.example.com/jellyfin');
    });

    test('rejects garbage', () {
      expect(() => normalizeBaseUrl(''), throwsA(isA<ApiException>()));
      expect(() => normalizeBaseUrl('ftp://nas'), throwsA(isA<ApiException>()));
    });
  });

  test('knows which audio the bundled libmpv decodes', () {
    expect(canDecodeAudio('truehd'), isFalse);
    expect(canDecodeAudio('TRUEHD'), isFalse);
    expect(canDecodeAudio('dts'), isTrue);
    expect(canDecodeAudio('pcm_s24be'), isTrue);
    expect(canDecodeAudio(null), isTrue);
    expect(codecLabel('eac3'), 'E-AC3');
  });
}
