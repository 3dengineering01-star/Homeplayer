import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/accounts_screen.dart';
import 'package:homeplay/services/own_server.dart';
import 'package:homeplay/widgets/own_server_guide.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _mine = Account(
    id: 'm', kind: ServerKind.jellyfin, baseUrl: 'http://192.168.1.5:8096', username: 'anna', serverName: 'Mine', token: 't', userId: 'u');
const _anna = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'https://anna.ts.net', username: 'Petr', serverName: "Anna's Homeplay", token: 't', userId: 'u', shared: true);
const _boris = Account(
    id: 'b', kind: ServerKind.jellyfin, baseUrl: 'https://boris.ts.net/', username: 'Petr', serverName: "Boris's Homeplay", token: 't', userId: 'u', shared: true);

void main() {
  test('only friends\' servers on the phone: the app shows how to make one\'s own', () {
    expect(needsOwnServer([]), isFalse);
    expect(needsOwnServer([_anna, _boris]), isTrue);
    expect(needsOwnServer([_anna, _mine]), isFalse);
    expect(sharedServers([_mine, _anna, _boris]), ['https://anna.ts.net', 'https://boris.ts.net/']);
    expect(setupLink('https://boris.ts.net/'), 'https://boris.ts.net/Homeplay/Setup');
    // Saved before the flag existed: one's own.
    final old = _mine.toJson()..remove('shared');
    expect(Account.fromJson(old).shared, isFalse);
    expect(_mine.toJson().containsKey('shared'), isFalse);
  });

  test('the installer comes from the first friend\'s server that gives it out', () async {
    final asked = <String>[];
    final link = await findSetupLink(
      ['https://anna.ts.net', 'https://boris.ts.net'],
      client: () => MockClient((r) async {
        asked.add(r.url.toString());
        return http.Response('', r.url.host == 'boris.ts.net' ? 200 : 404);
      }),
    );
    expect(link, 'https://boris.ts.net/Homeplay/Setup');
    expect(asked, ['https://anna.ts.net/Homeplay/Setup', 'https://boris.ts.net/Homeplay/Setup']);
    expect(await findSetupLink(['https://anna.ts.net'], client: () => MockClient((_) async => throw Exception('offline'))), isNull);
    expect(await findSetupLink([]), isNull);
    expect(setupMessage('https://x/Homeplay/Setup'), contains('https://x/Homeplay/Setup'));
  });

  Future<void> pumpGuide(WidgetTester tester, String? link, VoidCallback onAdd) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [OwnServerGuide(servers: const ['https://anna.ts.net'], onAdd: onAdd, findLink: (_) async => link)]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('the guide offers to send the installer link to the computer', (tester) async {
    var added = false;
    await pumpGuide(tester, 'https://anna.ts.net/Homeplay/Setup', () => added = true);
    expect(find.text('Your own Homeplay'), findsOneWidget);
    expect(find.text('Send the link to my computer'), findsOneWidget);
    expect(find.textContaining('Ask whoever'), findsNothing);
    await tester.ensureVisible(find.text('Add your server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add your server'));
    expect(added, isTrue);
  });

  testWidgets('without the installer on the server the guide says whom to ask', (tester) async {
    await pumpGuide(tester, null, () {});
    expect(find.text('Send the link to my computer'), findsNothing);
    expect(find.textContaining('HomeplaySetup.exe'), findsOneWidget);
  });

  testWidgets('the server list shows the way to one\'s own server when all servers are friends\'', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'accounts': jsonEncode([_anna.toJson(), _boris.toJson()]),
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AccountsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Your own Homeplay'), 200);
    expect(find.text('Your own Homeplay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with one\'s own server there is no such card', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'accounts': jsonEncode([_anna.toJson(), _mine.toJson()]),
    });
    await tester.pumpWidget(const MaterialApp(home: AccountsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Your own Homeplay'), findsNothing);
  });
}
