import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/services/video_extras.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _account = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'me');

int _ticks(int seconds) => seconds * 10000000;

Map<String, dynamic> _segment(String type, int from, int to) =>
    {'Id': 'x', 'ItemId': 'ep', 'Type': type, 'StartTicks': _ticks(from), 'EndTicks': _ticks(to)};

Map<String, dynamic> _tiles(int width, {int count = 250, int interval = 10000}) => {
      'Width': width,
      'Height': width * 9 ~/ 16,
      'TileWidth': 10,
      'TileHeight': 10,
      'ThumbnailCount': count,
      'Interval': interval,
      'Bandwidth': 1000,
    };

void main() {
  group('intro and credits', () {
    final segments = parseSegments({
      'Items': [
        _segment('Outro', 1300, 1380),
        _segment('Intro', 60, 150),
        _segment('Unknown', 200, 300),
        _segment('Recap', 0, 2),
        {'Type': 'Intro'},
      ],
    });

    test('come in time order, only those worth a button', () {
      expect(segments, [
        const MediaSegment(SegmentKind.intro, Duration(seconds: 60), Duration(seconds: 150)),
        const MediaSegment(SegmentKind.outro, Duration(seconds: 1300), Duration(seconds: 1380)),
      ]);
    });

    test('an answer of another shape is nothing', () {
      expect(parseSegments(null), isEmpty);
      expect(parseSegments('nope'), isEmpty);
      expect(parseSegments({'Items': 'x'}), isEmpty);
    });

    test('the button shows from the start until a second before the end', () {
      expect(skippableAt(segments, const Duration(seconds: 59)), isNull);
      expect(skippableAt(segments, const Duration(seconds: 60))?.kind, SegmentKind.intro);
      expect(skippableAt(segments, const Duration(seconds: 148))?.kind, SegmentKind.intro);
      expect(skippableAt(segments, const Duration(milliseconds: 149500)), isNull);
      expect(skippableAt(segments, const Duration(seconds: 1350))?.kind.label, 'Skip credits');
    });

    test('credits to the very end go to the next episode, others only to their end', () {
      final credits = segments.last;
      expect(endsVideo(credits, const Duration(seconds: 1382)), isTrue);
      expect(endsVideo(credits, const Duration(seconds: 1500)), isFalse, reason: 'a scene after the credits');
      expect(endsVideo(credits, null), isFalse);
      expect(endsVideo(segments.first, const Duration(seconds: 152)), isFalse, reason: 'not credits');
    });
  });

  group('pictures for seeking', () {
    test('the size closest above 320, else the largest', () {
      expect(parseTrickplay({'src': {'160': _tiles(160), '320': _tiles(320), '640': _tiles(640)}}, 'src')?.width, 320);
      expect(parseTrickplay({'src': {'480': _tiles(480), '960': _tiles(960)}}, 'src')?.width, 480);
      expect(parseTrickplay({'src': {'160': _tiles(160), '240': _tiles(240)}}, 'src')?.width, 240);
    });

    test('of the chosen file; the only one when none is named', () {
      final field = {'a': {'320': _tiles(320, count: 5)}, 'b': {'320': _tiles(320, count: 7)}};
      expect(parseTrickplay(field, 'b')?.count, 7);
      expect(parseTrickplay(field, null), isNull, reason: 'two files, which one is unknown');
      expect(parseTrickplay({'a': {'320': _tiles(320, count: 5)}}, null)?.count, 5);
      expect(parseTrickplay({}, 'a'), isNull);
      expect(parseTrickplay(null, 'a'), isNull);
      expect(parseTrickplay({'a': {'320': {'Width': 320}}}, 'a'), isNull);
    });

    test('a time is found on its sheet, row by row', () {
      final t = parseTrickplay({'s': {'320': _tiles(320, count: 250)}}, 's')!;
      expect(t.tileAt(Duration.zero), (sheet: 0, column: 0, row: 0));
      expect(t.tileAt(const Duration(seconds: 125)), (sheet: 0, column: 2, row: 1));
      expect(t.tileAt(const Duration(seconds: 1000)), (sheet: 1, column: 0, row: 0));
      // Past the last picture: the last one, not a sheet that does not exist.
      expect(t.tileAt(const Duration(hours: 5)), (sheet: 2, column: 9, row: 4));
    });

    test('a short video still has its pictures on the first sheet', () {
      final t = parseTrickplay({'s': {'320': _tiles(320, count: 3)}}, 's')!;
      expect(t.tileAt(const Duration(seconds: 24)), (sheet: 0, column: 2, row: 0));
      expect(t.tileAt(const Duration(seconds: 90)), (sheet: 0, column: 2, row: 0));
    });
  });

  group('asked from Jellyfin', () {
    JellyfinClient client(Future<http.Response> Function(http.Request r) answer) =>
        JellyfinClient(_account, 'dev', client: MockClient(answer));

    test('segments and pictures together', () async {
      final x = await client((r) async {
        if (r.url.path == '/MediaSegments/ep') {
          return http.Response(jsonEncode({'Items': [_segment('Intro', 10, 70)]}), 200);
        }
        expect(r.url.path, '/Items/ep');
        expect(r.url.queryParameters['fields'], contains('Trickplay'));
        return http.Response(
            jsonEncode({
              'Id': 'ep',
              'MediaSources': [{'Id': 'src'}],
              'Trickplay': {'src': {'320': _tiles(320)}},
            }),
            200);
      }).videoExtras('ep');
      expect(x!.segments.single.kind, SegmentKind.intro);
      expect(x.canPreview, isTrue);
      final url = x.sheetUrl!(2);
      expect(url.path, '/Videos/ep/Trickplay/320/2.jpg');
      expect(url.queryParameters['mediaSourceId'], 'src');
      expect(url.queryParameters.containsKey('ApiKey'), isFalse, reason: 'the token goes in the header');
    });

    test('an older server without segments still gives the pictures', () async {
      final x = await client((r) async => r.url.path.startsWith('/MediaSegments')
          ? http.Response('', 404)
          : http.Response(jsonEncode({'Id': 'ep', 'Trickplay': {'v2': {'320': _tiles(320)}}}), 200)).videoExtras('ep', versionId: 'v2');
      expect(x!.segments, isEmpty);
      expect(x.sheetUrl!(0).queryParameters['mediaSourceId'], 'v2');
    });

    test('no answer at all is null; a server with neither has nothing to show', () async {
      expect(await client((_) async => throw http.ClientException('offline')).videoExtras('ep'), isNull);
      final none = await client((r) async =>
          http.Response(jsonEncode(r.url.path.startsWith('/MediaSegments') ? {'Items': []} : {'Id': 'ep'}), 200)).videoExtras('ep');
      expect(none!.segments, isEmpty);
      expect(none.canPreview, isFalse);
    });
  });
}
