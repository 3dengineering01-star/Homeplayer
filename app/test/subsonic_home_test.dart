import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/subsonic.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/subsonic_browser.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _account = Account(
    id: 'b', kind: ServerKind.subsonic, baseUrl: 'http://nas:4533', username: 'u', serverName: 'Music', token: 'tok', salt: 's');

http.Response _ok(Map<String, dynamic> body) =>
    http.Response(jsonEncode({'subsonic-response': {'status': 'ok', ...body}}), 200);

SubsonicClient _server({bool oldServer = false}) => SubsonicClient(_account, client: MockClient((r) async {
      final q = r.url.queryParameters;
      return switch (r.url.path) {
        '/rest/getAlbumList2' when oldServer && q['type'] != 'newest' =>
          http.Response(jsonEncode({'subsonic-response': {'status': 'failed', 'error': {'code': 0, 'message': 'no'}}}), 200),
        '/rest/getAlbumList2' => _ok({
            'albumList2': {
              'album': q['type'] == 'frequent'
                  ? []
                  : [
                      {'id': '${q['type']}1', 'name': 'Mannavegr (${q['type']})', 'artist': 'Danheim', 'coverArt': 'c1'},
                    ],
            },
          }),
        '/rest/getStarred2' => _ok({
            'starred2': {
              'song': [
                {'id': 's1', 'title': 'Gripir', 'artist': 'Danheim', 'starred': '2026-01-01'},
              ],
            },
          }),
        '/rest/getArtists' => _ok({'artists': {'index': []}}),
        _ => http.Response('', 404),
      };
    }));

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets('Navidrome opens on Home: new, played, favorite albums and songs, at text size $scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: SubsonicArtists(client: _server(), title: 'Music'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Shuffle all'), findsOneWidget);
      expect(find.text('Recently added'), findsOneWidget);
      expect(find.text('Mannavegr (newest)'), findsOneWidget);
      expect(find.text('Recently played'), findsOneWidget);
      expect(find.text('Most played'), findsNothing, reason: 'nothing played often yet');
      expect(find.text('Favorite albums', skipOffstage: false), findsOneWidget);
      expect(find.text('Gripir', skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an old server without some lists still shows what it has', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SubsonicArtists(client: _server(oldServer: true), title: 'Music')));
    await tester.pumpAndSettle();
    expect(find.text('Mannavegr (newest)'), findsOneWidget);
    expect(find.text('Recently played'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
