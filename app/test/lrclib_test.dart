import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/api/lrclib.dart';
import 'package:homeplay/services/track_lookup.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _studio = {
  'trackName': 'Time',
  'artistName': 'Pink Floyd',
  'duration': 413.0,
  'plainLyrics': 'Ticking away\nthe moments',
  'syncedLyrics': '[00:01.00]Ticking away\n[00:04.50]the moments',
};
const _live = {
  'trackName': 'Time (live)',
  'artistName': 'Pink Floyd',
  'duration': 470.0,
  'plainLyrics': 'Live words',
  'syncedLyrics': null,
};

void main() {
  test('the recording of the right length wins, timed lyrics before plain', () {
    expect(pickLrcLib([_live, _studio], const Duration(seconds: 412))?['trackName'], 'Time');
    expect(pickLrcLib([_live, _studio], const Duration(seconds: 469))?['trackName'], 'Time (live)');
    // Length unknown: the timed ones.
    expect(pickLrcLib([_live, _studio], null)?['trackName'], 'Time');
    // Nothing near that length (a converted stream's guess): the closest timed lyrics anyway.
    expect(pickLrcLib([_live, _studio], const Duration(seconds: 364))?['trackName'], 'Time');
    expect(pickLrcLib('nonsense', null), isNull);
  });

  test('a result becomes timed lines, says where it came from; an instrumental says so', () {
    final l = lyricsFromLrcLib(_studio)!;
    expect(l.synced, isTrue);
    expect(l.lines.first.text, 'Ticking away');
    expect(l.lines.last.start, const Duration(milliseconds: 4500));
    expect(l.source, 'LRCLIB');
    expect(lyricsFromLrcLib({'instrumental': true})!.lines.single.text, contains('Instrumental'));
    expect(lyricsFromLrcLib({'plainLyrics': '  '}), isNull);
  });

  group('when the server has none', () {
    final song = PlayItem(title: 'Time', subtitle: 'Pink Floyd, David Gilmour', url: Uri.parse('http://nas/a.flac'), isVideo: false);

    test('LRCLIB is asked by title and artist, the first artist alone if needed', () async {
      SharedPreferences.setMockInitialValues({});
      final asked = <Uri>[];
      final client = MockClient((r) async {
        asked.add(r.url);
        expect(r.headers['User-Agent'], contains('OwnMedia'));
        final first = r.url.queryParameters['artist_name'] == 'Pink Floyd';
        return http.Response(jsonEncode(first ? [_studio] : []), 200);
      });
      final l = await TrackLookup.lyrics(song, duration: const Duration(seconds: 413), lrclib: LrcLib(client: client));
      expect(l?.lines.first.text, 'Ticking away');
      expect(asked.map((u) => u.queryParameters['artist_name']), ['Pink Floyd, David Gilmour', 'Pink Floyd']);
      expect(asked.first.host, 'lrclib.net');
      expect(asked.first.queryParameters['track_name'], 'Time');
    });

    test('turned off in the settings, nothing leaves the phone', () async {
      SharedPreferences.setMockInitialValues({'lyrics_lrclib': false});
      var asked = false;
      final client = MockClient((r) async {
        asked = true;
        return http.Response('[]', 200);
      });
      expect(await TrackLookup.lyrics(song, lrclib: LrcLib(client: client)), isNull);
      expect(asked, isFalse);
    });
  });
}
