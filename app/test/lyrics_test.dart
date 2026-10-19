import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/lyrics.dart';

void main() {
  test('Jellyfin lyrics keep their times; ticks become durations', () {
    final l = lyricsFromJellyfin({
      'Lyrics': [
        {'Text': '', 'Start': 0},
        {'Text': 'First line', 'Start': 125000000},
        {'Text': 'Second line', 'Start': 250000000},
        {'Text': ''},
      ],
    })!;
    expect(l.synced, isTrue);
    expect(l.lines.map((x) => x.text), ['First line', 'Second line']);
    expect(l.lines.first.start, const Duration(milliseconds: 12500));
  });

  test('Jellyfin lyrics without times are plain text; no words is no lyrics', () {
    final l = lyricsFromJellyfin({
      'Lyrics': [
        {'Text': 'One'},
        {'Text': ''},
        {'Text': 'Two'},
      ],
    })!;
    expect(l.synced, isFalse);
    expect(l.lines.map((x) => x.text), ['One', '', 'Two']);
    expect(lyricsFromJellyfin({'Lyrics': []}), isNull);
    expect(lyricsFromJellyfin(null), isNull);
  });

  test('OpenSubsonic picks the timed version and applies the offset', () {
    final l = lyricsFromOpenSubsonic({
      'structuredLyrics': [
        {
          'synced': false,
          'line': [
            {'value': 'plain'},
          ],
        },
        {
          'synced': true,
          'offset': 500,
          'line': [
            {'start': 1000, 'value': 'Hello'},
            {'start': 3000, 'value': 'World'},
          ],
        },
      ],
    })!;
    expect(l.synced, isTrue);
    expect(l.lines.map((x) => x.start), [const Duration(milliseconds: 500), const Duration(milliseconds: 2500)]);
  });

  test('LRC text: tags skipped, several times on a line, sorted, offset applied', () {
    final l = lyricsFromText('[ar:Someone]\n[offset:+200]\n[00:05.50]Second\n[00:01.00][00:10.2]Chorus\n')!;
    expect(l.synced, isTrue);
    expect([for (final x in l.lines) (x.start!.inMilliseconds, x.text)],
        [(800, 'Chorus'), (5300, 'Second'), (10000, 'Chorus')]);
  });

  test('plain text stays as it is', () {
    final l = lyricsFromText('Line one\r\nLine two\n')!;
    expect(l.synced, isFalse);
    expect(l.lines.map((x) => x.text), ['Line one', 'Line two']);
    expect(lyricsFromText('  \n '), isNull);
    expect(lyricsFromText(null), isNull);
  });

  test('the current line is the last one started', () {
    const lines = [
      LyricLine('a', Duration(seconds: 1)),
      LyricLine('b', Duration(seconds: 5)),
      LyricLine('c', Duration(seconds: 9)),
    ];
    expect(currentLyricLine(lines, Duration.zero), -1);
    expect(currentLyricLine(lines, const Duration(seconds: 1)), 0);
    expect(currentLyricLine(lines, const Duration(seconds: 6)), 1);
    expect(currentLyricLine(lines, const Duration(minutes: 3)), 2);
    expect(currentLyricLine(const [], const Duration(seconds: 3)), -1);
  });
}
