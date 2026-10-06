import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/services/downloads.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const nas = Account(
    id: 'jf:nas', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'x');
const music = Account(
    id: 'ss:music', kind: ServerKind.subsonic, baseUrl: 'http://music', username: 'u', serverName: 'Navidrome', token: 't', salt: 's');

void main() {
  test('watched past 90%, as Jellyfin counts it', () {
    const hour = Duration(hours: 1);
    expect(isWatched(const Duration(minutes: 55), hour), isTrue);
    expect(isWatched(const Duration(minutes: 50), hour), isFalse);
    expect(isWatched(hour, null), isFalse);
  });

  test('downloads from before keep loading, with nothing played', () {
    final old = DownloadEntry.fromJson({'id': 'a', 'title': 'Film', 'isVideo': true, 'state': 'done'});
    expect((old.accountId, old.position, old.watched, old.unsynced), (null, Duration.zero, false, false));
    final played = old.copyWith(position: const Duration(minutes: 7), unsynced: true, duration: const Duration(hours: 2));
    final back = DownloadEntry.fromJson(jsonDecode(jsonEncode(played.toJson())) as Map<String, dynamic>);
    expect((back.position, back.unsynced, back.duration), (const Duration(minutes: 7), true, const Duration(hours: 2)));
  });

  test('a watched download reaches the server as played to the end, even after a replay', () {
    const e = DownloadEntry(
        id: 'a', title: 'Film', isVideo: true, watched: true, position: Duration(minutes: 3), duration: Duration(hours: 2));
    expect(e.reportedPosition, const Duration(hours: 2));
    expect(e.copyWith(watched: false).reportedPosition, const Duration(minutes: 3));
  });

  test('old downloads go to the only Jellyfin server; with several, nowhere', () {
    expect(accountFor([nas, music], null), nas);
    expect(accountFor([nas, music], 'jf:nas'), nas);
    expect(accountFor([nas, nas], null), isNull);
    expect(accountFor([music], 'jf:gone'), isNull);
  });

  test('play reports go as stop reports; a refused one is kept for later', () async {
    final bodies = <Map<String, dynamic>>[];
    var serverUp = false;
    final client = JellyfinClient(nas, 'dev', client: MockClient((r) async {
      expect(r.url.path, '/Sessions/Playing/Stopped');
      bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response('', serverUp ? 204 : 503);
    }));
    const pending = [
      DownloadEntry(id: 'a', title: 'A', isVideo: true, position: Duration(minutes: 10), unsynced: true),
      DownloadEntry(id: 'b', title: 'B', isVideo: true, position: Duration(seconds: 5), unsynced: true),
    ];
    expect(await sendPlayed(pending, (_) async => client), isEmpty);
    serverUp = true;
    expect(await sendPlayed(pending, (_) async => client), {'a', 'b'});
    expect(bodies.last, {'ItemId': 'b', 'MediaSourceId': 'b', 'PlayMethod': 'DirectPlay', 'PositionTicks': 50000000});
    expect(await sendPlayed(pending, (_) async => null), isEmpty); // no server for them
  });

  test('failed reports are tried again, soon at first, then at most every 5 minutes', () {
    expect([for (var n = 0; n < 7; n++) retryDelay(n).inSeconds], [15, 30, 60, 120, 240, 300, 300]);
  });

  test('without a connection the report fails quietly', () async {
    final client = JellyfinClient(nas, 'dev', client: MockClient((_) async => throw http.ClientException('offline')));
    expect(await client.reportPlayed('a', Duration.zero), isFalse);
  });
}
