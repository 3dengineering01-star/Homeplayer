import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/api/subsonic.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/widgets/music_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _jf = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'me');
const _ss = Account(
    id: 'b', kind: ServerKind.subsonic, baseUrl: 'http://nas:4533', username: 'u', serverName: 'Music', token: 'tok', salt: 's');

JellyfinItem _track(String id, {bool favorite = false}) =>
    JellyfinItem({'Id': id, 'Name': id, 'Type': 'Audio', 'UserData': {'IsFavorite': favorite}});

void main() {
  test('a heart goes to the server, and a refusal takes it back', () async {
    final seen = <http.Request>[];
    var fail = false;
    final c = JellyfinClient(_jf, 'dev', client: MockClient((r) async {
      seen.add(r);
      return http.Response('', fail ? 500 : 204);
    }));
    final item = c.toPlayItem(_track('t1'));
    final fav = item.favorite!;
    expect(fav.marked.value, isFalse);
    await fav.toggle();
    expect(fav.marked.value, isTrue);
    expect(seen.last.method, 'POST');
    expect(seen.last.url.path, '/UserFavoriteItems/t1');
    expect(seen.last.url.queryParameters['userId'], 'me');
    // A list loaded before still says "not a favorite": the heart set since wins.
    expect(c.isFavorite(_track('t1')), isTrue);
    expect(c.toPlayItem(_track('t1')).favorite!.marked.value, isTrue);

    fail = true;
    await expectLater(fav.toggle(), throwsA(isA<ApiException>()));
    expect(fav.marked.value, isTrue, reason: 'the server refused: the heart stays as it was');
    fail = false;
    await fav.toggle();
    expect(seen.last.method, 'DELETE');
    expect(fav.marked.value, isFalse);
  });

  test('videos have no heart; favorites are asked for as tracks marked so', () async {
    final seen = <http.Request>[];
    final c = JellyfinClient(_jf, 'dev', client: MockClient((r) async {
      seen.add(r);
      return http.Response(jsonEncode({'Items': [], 'TotalRecordCount': 0}), 200);
    }));
    expect(c.toPlayItem(JellyfinItem({'Id': 'm', 'Name': 'Dune', 'Type': 'Movie'})).favorite, isNull);
    expect(c.toPlayItem(_track('t', favorite: true)).favorite!.marked.value, isTrue);
    await c.favoriteTracks();
    final q = seen.single.url.queryParameters;
    expect(q['filters'], 'IsFavorite');
    expect(q['includeItemTypes'], 'Audio');
    expect(q['recursive'], 'true');
  });

  test('on Subsonic the heart is a star', () async {
    final seen = <Uri>[];
    final c = SubsonicClient(_ss, client: MockClient((r) async {
      seen.add(r.url);
      return http.Response(jsonEncode({'subsonic-response': {'status': 'ok'}}), 200);
    }));
    final item = c.toPlayItem(const SubsonicEntry(id: 's1', title: 'Gripir', starred: true));
    expect(item.favorite!.marked.value, isTrue);
    await item.favorite!.toggle();
    expect(seen.single.path, '/rest/unstar');
    expect(seen.single.queryParameters['id'], 's1');
  });

  testWidgets('the heart in the player shows and flips the mark', (tester) async {
    final fav = ServerFavorite(false, (_) async {});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: FavoriteButton(favorite: fav)))));
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byTooltip('Add to favorites'), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
  });
}
