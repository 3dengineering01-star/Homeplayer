import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _account = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'x');

final movie = JellyfinItem({'Id': 'i', 'Name': 'Film', 'MediaType': 'Video', 'Type': 'Movie'});

/// Like Jellyfin with our profile: subtitles inside the file are embedded when it plays as it
/// is; in a converted stream text ones become files and picture ones are dropped.
JellyfinClient server({required int fileBitrate}) => JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async {
        final converting = (jsonDecode(r.body) as Map)['EnableDirectPlay'] == false;
        Map<String, dynamic> sub(int index, String codec, String lang, {bool external = false}) {
          final asFile = external || (converting && codec != 'PGSSUB');
          return {
            'Type': 'Subtitle',
            'Index': index,
            'Codec': codec,
            'Language': lang,
            'IsExternal': external,
            'DeliveryMethod': asFile ? 'External' : (converting ? 'Encode' : 'Embed'),
            if (asFile) 'DeliveryUrl': '/Videos/i/m/Subtitles/$index/0/Stream.${codec == 'ass' ? 'ass' : 'srt'}',
          };
        }

        return http.Response(
            jsonEncode({
              'PlaySessionId': 's',
              'MediaSources': [
                {
                  'Id': 'm',
                  'Bitrate': fileBitrate,
                  'DefaultAudioStreamIndex': 1,
                  'MediaStreams': [
                    {'Type': 'Video', 'Index': 0, 'Codec': 'h264'},
                    {'Type': 'Audio', 'Index': 1, 'Codec': 'aac', 'Channels': 2},
                    sub(2, 'ass', 'eng'),
                    sub(3, 'PGSSUB', 'eng'),
                    sub(4, 'subrip', 'rus', external: true),
                  ],
                  if (converting) 'TranscodingUrl': '/videos/i/master.m3u8',
                },
              ],
            }),
            200);
      }),
    );

void main() {
  test('playing the file: only the .srt next to it comes as a file', () async {
    final item = await server(fileBitrate: 5000000).resolve(movie);
    expect(item.subtitles, hasLength(1));
    final srt = item.subtitles.single;
    expect(srt.language, 'rus');
    expect(srt.title, 'External');
    expect(srt.url.toString(), 'http://nas:8096/Videos/i/m/Subtitles/4/0/Stream.srt?ApiKey=t');
  });

  test('a converted video gets its text subtitles as files and says the picture ones are off', () async {
    final item = await server(fileBitrate: 40000000).resolve(movie, cap: 4000000);
    expect(item.convertedTo, 4000000);
    expect([for (final s in item.subtitles) s.url.pathSegments.last], ['Stream.ass', 'Stream.srt']);
    expect(item.notice, contains('Picture subtitles are off'));
  });

  test('a token already in the URL is not added twice', () {
    final client = JellyfinClient(_account, 'dev');
    final subs = client.deliveredSubtitles({
      'MediaStreams': [
        {'Type': 'Subtitle', 'DeliveryMethod': 'External', 'DeliveryUrl': '/s.srt?api_key=t', 'Title': 'Forced'},
        {'Type': 'Subtitle', 'DeliveryMethod': 'Embed'},
      ],
    });
    expect(subs.single.url.toString(), 'http://nas:8096/s.srt?api_key=t');
    expect(subs.single.title, 'Forced');
    expect(client.losesSubtitles({'MediaStreams': []}), isFalse);
  });
}
