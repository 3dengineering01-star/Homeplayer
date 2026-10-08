import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/accounts_screen.dart';
import 'package:homeplay/services/server_status.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _jellyfin = Account(
    id: 'j', kind: ServerKind.jellyfin, baseUrl: 'http://192.168.1.5:8096', username: 'anna', serverName: 'GOODMAN', token: 't', userId: 'u');
const _navidrome = Account(
    id: 's', kind: ServerKind.subsonic, baseUrl: 'http://my-very-long-home-server-name.tail1234.ts.net:4533', username: 'anna', serverName: 'Navidrome · nas with a long name', token: 't', salt: 's');

void main() {
  test('the greeting follows the time of day', () {
    expect(greeting(DateTime(2026, 10, 7, 7)), 'Good morning');
    expect(greeting(DateTime(2026, 10, 7, 13)), 'Good afternoon');
    expect(greeting(DateTime(2026, 10, 7, 21)), 'Good evening');
    expect(greeting(DateTime(2026, 10, 7, 2)), 'Good night');
  });

  test('a server answers when its public page does', () async {
    final seen = <Uri>[];
    final up = MockClient((r) async {
      seen.add(r.url);
      return http.Response('{}', 200);
    });
    expect(await serverAnswers(_jellyfin, client: up), isTrue);
    expect(await serverAnswers(_navidrome, client: up), isTrue);
    expect(seen.map((u) => u.path), ['/System/Info/Public', '/rest/ping.view']);
    expect(await serverAnswers(_jellyfin, client: MockClient((_) async => http.Response('', 503))), isFalse);
    expect(await serverAnswers(_jellyfin, client: MockClient((_) async => throw Exception('no route'))), isFalse);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('the server list draws two servers at text size $scale', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'accounts': jsonEncode([_jellyfin.toJson(), _navidrome.toJson()]),
      });
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery.withClampedTextScaling(minScaleFactor: scale, maxScaleFactor: scale, child: const AccountsScreen()),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('GOODMAN'), findsOneWidget);
      expect(find.text('Jellyfin · anna'), findsOneWidget);
      // With big letters the card is below the fold.
      await tester.scrollUntilVisible(find.text('Add a server'), 200);
      expect(find.text('Add a server'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('GOODMAN'), -200);
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      expect(find.text('Photo backup'), findsOneWidget);
      expect(find.text('Remove server'), findsOneWidget);
    });
  }

  testWidgets('with no server the list welcomes and offers to add one', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: AccountsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Add your server'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
