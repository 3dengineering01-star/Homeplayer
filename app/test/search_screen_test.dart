import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/search_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _account = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'me');

final _files = [
  {
    'Id': 'c1', 'Name': 'Cluster One', 'Type': 'Audio', 'Album': 'The Division Bell', 'AlbumId': 'bell',
    'AlbumArtist': 'Pink Floyd', 'Artists': ['Pink Floyd'], 'Path': r'D:\Music\Bell\01-Cluster One.mp3',
  },
  {
    'Id': 'c2', 'Name': 'Poles Apart', 'Type': 'Audio', 'Album': 'The Division Bell', 'AlbumId': 'bell',
    'AlbumArtist': 'Pink Floyd', 'Artists': ['Pink Floyd'], 'Path': r'D:\Music\Bell\03-Poles Apart.mp3',
  },
];

JellyfinClient _server() => JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async {
        final q = r.url.queryParameters;
        final items = switch (r.url.path) {
          '/Items' when q['includeItemTypes'] == 'Playlist' => [
              {'Id': 'pl', 'Name': 'Road trip', 'Type': 'Playlist', 'ChildCount': 1},
            ],
          '/Playlists/pl/Items' => [_files.first],
          '/Items' when q['searchTerm'] == null => _files,
          _ => <Map<String, Object>>[],
        };
        return http.Response(jsonEncode({'Items': items, 'TotalRecordCount': items.length}), 200);
      }),
    );

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets('typed letters show the track, its album, folder and playlist at once (text $scale)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: SearchScreen(client: _server()),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'clus');
      // Before the server is asked: the phone's own list answers.
      await tester.pump();
      expect(find.textContaining('Tracks · 1'), findsOneWidget);
      expect(find.textContaining('Albums · 1'), findsOneWidget);
      expect(find.textContaining('Folders · 1'), findsOneWidget);
      expect(find.textContaining('Playlists · 1'), findsOneWidget);
      expect(find.textContaining('Has: Cluster One', findRichText: true), findsNWidgets(3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
