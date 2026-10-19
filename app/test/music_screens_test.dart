import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/music_library_screen.dart';
import 'package:homeplay/screens/track_list_screen.dart';
import 'package:homeplay/widgets/alphabet_bar.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      'DateCreated': '2026-10-0${i + 1}T00:00:00Z',
      'UserData': {'PlayCount': i, if (i > 0) 'LastPlayedDate': '2026-10-1${i}T00:00:00Z'},
      'Path': i < 3 ? 'D:\\Music\\Folk\\Danheim\\Mannavegr\\0$i $name.flac' : 'D:\\Music\\Rock\\Pink Floyd\\$name.mp3',
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
      // Home first: what is new and what was played.
      expect(find.text('Shuffle all 5'), findsOneWidget);
      expect(find.text('Recently added'), findsOneWidget);
      expect(find.text('Recently played'), findsOneWidget);
      expect(find.text('Most played', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final tab in ['Artists', 'Albums', 'Tracks', 'Folders', 'Playlists']) {
        // With big letters the tabs scroll: the last ones are off to the side.
        await tester.ensureVisible(find.text(tab));
        await tester.pumpAndSettle();
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
        if (tab == 'Artists') {
          expect(find.text('Danheim'), findsWidgets);
          expect(find.text('Pink Floyd'), findsOneWidget);
        }
        if (tab == 'Folders') {
          expect(find.text('Folk'), findsOneWidget);
          expect(find.text('Rock'), findsOneWidget);
        }
      }
      expect(find.text('Road'), findsOneWidget);
      expect(find.text('New playlist'), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
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

  testWidgets('a track name typed on the Artists tab finds its artist, album and the track', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MusicLibraryScreen(
        client: _server(),
        library: JellyfinItem({'Id': 'lib', 'Name': 'Музыка', 'Type': 'CollectionFolder', 'CollectionType': 'music'}),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'gripir');
    await tester.pumpAndSettle();
    expect(find.text('Artists · 1'), findsOneWidget);
    expect(find.text('Albums · 1'), findsOneWidget);
    expect(find.text('Tracks · 1'), findsOneWidget);
    expect(find.textContaining('Has: Gripir', findRichText: true), findsOneWidget);
    // Nothing among the artists: the screen moves to the tab that has it.
    await tester.enterText(find.byType(TextField), 'money with');
    await tester.pumpAndSettle();
    expect(find.text('Tracks · 1'), findsOneWidget);
    expect(find.text('Artists · 1'), findsOneWidget, reason: 'Pink Floyd holds it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the letters beside a long artist list jump to the artists of a letter', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'music.tab_name': 'Artists'});
    // 26 letters, two artists each.
    final many = [
      for (var c = 0; c < 26; c++)
        for (final n in [1, 2])
          {
            'Id': 'x$c$n',
            'Name': 'Song',
            'Type': 'Audio',
            'Artists': ['${String.fromCharCode(65 + c)}rtist $n'],
          },
    ];
    final client = JellyfinClient(
      _account,
      'dev',
      client: MockClient((r) async => switch (r.url.path) {
            '/Items' when r.url.queryParameters['includeItemTypes'] == 'Playlist' =>
              http.Response(jsonEncode({'Items': []}), 200),
            '/Items' => http.Response(jsonEncode({'Items': many, 'TotalRecordCount': many.length}), 200),
            _ => http.Response('', 404),
          }),
    );
    await tester.pumpWidget(MaterialApp(
      home: MusicLibraryScreen(
        client: client,
        library: JellyfinItem({'Id': 'lib', 'Name': 'Music', 'Type': 'CollectionFolder', 'CollectionType': 'music'}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AlphabetBar), findsOneWidget);
    expect(find.text('Trtist 1'), findsNothing);
    await tester.tap(find.descendant(of: find.byType(AlphabetBar), matching: find.text('T')));
    await tester.pumpAndSettle();
    expect(find.text('Trtist 1'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Trtist 1')).dy, lessThan(400), reason: 'at the top of the list');
    expect(tester.takeException(), isNull);
  });
}
