import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/services/track_choice.dart';
import 'package:media_kit/media_kit.dart';

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

  test('formats durations like a player', () {
    expect(formatDuration(const Duration(minutes: 4, seconds: 7)), '4:07');
    expect(formatDuration(const Duration(hours: 1, minutes: 5, seconds: 9)), '1:05:09');
  });

  group('track choice', () {
    final tracks = [
      AudioTrack.auto(),
      AudioTrack('1', 'Main', 'eng', codec: 'truehd', channelscount: 8),
      AudioTrack('2', null, 'eng', codec: 'ac3', channelscount: 6),
      AudioTrack('3', null, 'rus', codec: 'aac', channelscount: 2),
    ];

    test('remembered language wins, among tracks the phone can decode', () {
      expect(chooseAudio(tracks, preferredLanguage: 'rus')?.id, '3');
      expect(chooseAudio(tracks, preferredLanguage: 'eng')?.id, '2'); // not the TrueHD one
    });

    test("falls back to the forced track, or keeps mpv's pick", () {
      expect(chooseAudio(tracks, preferredLanguage: 'jpn', forcedId: '2')?.id, '2');
      expect(chooseAudio(tracks, preferredLanguage: 'jpn'), isNull);
    });

    test('subtitles: off, a language, or no opinion', () {
      final subs = [SubtitleTrack('1', null, 'eng'), SubtitleTrack('2', null, 'rus')];
      expect(chooseSubtitle(subs, 'off')?.id, 'no');
      expect(chooseSubtitle(subs, 'rus')?.id, '2');
      expect(chooseSubtitle(subs, null), isNull);
    });

    test('labels read like a menu', () {
      expect(audioLabel(tracks[2]), 'English · AC3 · 5.1');
      expect(subtitleLabel(SubtitleTrack('1', 'Forced', 'rus', codec: 'subrip')), 'Русский · Forced · SRT');
    });

    test('tracks that read the same get numbered', () {
      expect(distinctLabels(['MP3', 'MP3', 'AAC']), ['MP3 · Track 1', 'MP3 · Track 2', 'AAC']);
    });
  });
}
