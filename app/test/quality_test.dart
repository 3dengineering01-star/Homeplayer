import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/services/quality.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _account = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'x');

/// PlaybackInfo that answers like Jellyfin: the file, or a conversion when direct play is off.
JellyfinClient server({required int fileBitrate, List<Map<String, dynamic>>? bodies}) => JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        bodies?.add(body);
        final converting = body['EnableDirectPlay'] == false;
        return http.Response(
            jsonEncode({
              'PlaySessionId': 's',
              'MediaSources': [
                {
                  'Id': 'm',
                  'Bitrate': fileBitrate,
                  'DefaultAudioStreamIndex': 1,
                  'MediaStreams': [
                    {'Type': 'Video', 'Index': 0, 'Codec': 'hevc'},
                    {'Type': 'Audio', 'Index': 1, 'Codec': 'eac3', 'Channels': 6},
                  ],
                  if (converting) 'TranscodingUrl': '/videos/i/master.m3u8?MaxStreamingBitrate=${body['MaxStreamingBitrate']}',
                },
              ],
            }),
            200);
      }),
    );

final movie = JellyfinItem({'Id': 'i', 'Name': 'Film', 'MediaType': 'Video', 'Type': 'Movie'});

void main() {
  test('settings: labels, caps and how they are stored', () {
    expect(VideoQuality.choices.map((q) => q.label).take(4), ['Original', 'Auto', '20 Mbit/s', '10 Mbit/s']);
    expect(bitrateLabel(1500000), '1.5 Mbit/s');
    for (final q in VideoQuality.choices) {
      expect(VideoQuality.fromPref(q.toPref()), q);
    }
    expect(VideoQuality.fromPref(null), VideoQuality.original);
  });

  test('auto takes 70% of the measured speed, within sane limits', () {
    expect(capFor(VideoQuality.original), isNull);
    expect(capFor(const VideoQuality.capped(4000000)), 4000000);
    expect(capFor(VideoQuality.auto, measured: 10e6), 7000000);
    expect(capFor(VideoQuality.auto, measured: 300e3), 1000000);
    expect(capFor(VideoQuality.auto, measured: 1e9), 120000000);
    expect(capFor(VideoQuality.auto), fallbackCap); // the test failed
  });

  test('only files above the cap are converted', () {
    expect(needsConversion(30000000, 8000000), isTrue);
    expect(needsConversion(5000000, 8000000), isFalse);
    expect(needsConversion(30000000, null), isFalse);
    expect(needsConversion(null, 8000000), isFalse);
  });

  test('a file that fits plays as it is, and can still switch quality', () async {
    final item = await server(fileBitrate: 5000000).resolve(movie, cap: 8000000);
    expect(item.url.path, '/Videos/i/stream');
    expect(item.convertedTo, isNull);
    expect(item.withQuality, isNotNull);
  });

  test('a file above the cap is converted by the server to fit it', () async {
    final bodies = <Map<String, dynamic>>[];
    final item = await server(fileBitrate: 40000000, bodies: bodies).resolve(movie, cap: 4000000);
    expect(item.url.toString(), 'http://nas:8096/videos/i/master.m3u8?MaxStreamingBitrate=4000000');
    expect(item.convertedTo, 4000000);
    expect(item.notice, contains('4 Mbit/s'));
    expect(bodies.last, containsPair('AllowVideoStreamCopy', false));
    expect(bodies.last, containsPair('AudioStreamIndex', 1));
  });

  test('switching back to the original while playing', () async {
    final client = server(fileBitrate: 40000000);
    final converted = await client.resolve(movie, cap: 4000000);
    final original = await converted.withQuality!(VideoQuality.original);
    expect(original.convertedTo, isNull);
    expect(original.url.path, '/Videos/i/stream');
  });

  test('the speed test times test bytes from the server', () async {
    final client = JellyfinClient(_account, 'dev', client: MockClient((r) async {
      expect(r.url.path, '/Playback/BitrateTest');
      final size = int.parse(r.url.queryParameters['size']!);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return http.Response.bytes(List.filled(size, 0), 200);
    }));
    final measured = (await client.measureBitrate())!;
    // 500 KB in about 0.1 s is about 40 Mbit/s. On a busy machine the test's own overhead adds to
    // the time (it failed at 18.5 Mbit/s with many tests at once), so only the scale is checked.
    expect(measured, greaterThan(5e6));
    final failing = JellyfinClient(_account, 'dev', client: MockClient((_) async => http.Response('', 500)));
    expect(await failing.measureBitrate(), isNull);
  });
}
