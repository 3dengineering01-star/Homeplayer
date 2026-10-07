import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/music_library_screen.dart';
import 'package:homeplay/screens/track_list_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _account = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'me');

final _tracks = [
  for (final (i, name) in ['Vali', 'Gripir', 'Kala', 'Time', 'Money with a very long name that does not fit'].indexed)
    {
      'Id': 't$i',
      'Name': name,
      'Type': 'Audio',
      'Album': i < 3 ? 'Mannavegr' : null,
      'AlbumId': i < 3 ? 'm' : null,
      'AlbumArtist': i < 3 ? 'Danheim' : null,
      'Artists': i < 3 ? ['Danheim'] : ['Pink Floyd'],
      'IndexNumber': i + 1,
      'RunTimeTicks': 2000000000,
    },
];

JellyfinClient _server() => JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async => switch (r.url.path) {
            '/Items' when r.url.queryParameters['includeItemTypes'] == 'Playlist' => http.Response(
                jsonEncode({
                  'Items': [
                    {'Id': 'p', 'Name': 'Road', 'Type': 'Playlist', 'ChildCount': 2},
                  ],
                }),
                200),
            '/Items' => http.Response(jsonEncode({'Items': _tracks, 'TotalRecordCount': _tracks.length}), 200),
            _ => http.Response('', 404),
          }),
    );

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets('the music screen draws every tab at text size $scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: MusicLibraryScreen(
            client: _server(),
            library: JellyfinItem({'Id': 'lib', 'Name': 'Музыка', 'Type': 'CollectionFolder', 'CollectionType': 'music'}),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Danheim'), findsWidgets);
      expect(find.text('Pink Floyd'), findsOneWidget);
      for (final tab in ['Albums', 'Tracks', 'Playlists']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
      expect(find.text('Road'), findsOneWidget);
      expect(find.text('New playlist'), findsOneWidget);
    });

    testWidgets('an album page draws its header and tracks at text size $scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final tracks = [for (final t in _tracks) JellyfinItem(t)];
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: TrackListScreen(client: _server(), title: 'Mannavegr', subtitle: 'Danheim · 2018', load: () async => tracks, byAlbum: true),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('5 tracks · 16 min'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('Other tracks'), findsOneWidget);
    });
  }
}
