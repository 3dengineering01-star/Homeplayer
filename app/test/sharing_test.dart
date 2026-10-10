import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/api/sharing.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/share_screen.dart';
import 'package:homeplay/services/invite_link.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _owner = Account(
    id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'anna', serverName: "Anna's Homeplay", token: 't', userId: 'me');

final _libraries = [
  {'Id': 'm', 'Name': 'Movies', 'CollectionType': 'movies'},
  {'Id': 'p', 'Name': 'Photos', 'CollectionType': 'homevideos'},
];

void main() {
  group('invite links', () {
    test('the page address, alone or inside a message', () {
      expect(parseInvite('https://pc.tail1234.ts.net/Homeplay/Join/ABC23'), (server: 'https://pc.tail1234.ts.net', code: 'ABC23'));
      expect(
        parseInvite(inviteMessage("Anna's Homeplay", 'https://pc.ts.net/homeplay/join/XYZ9')),
        (server: 'https://pc.ts.net', code: 'XYZ9'),
      );
      expect(parseInvite('http://192.168.1.10:8096/Homeplay/Join/Q7'), (server: 'http://192.168.1.10:8096', code: 'Q7'));
    });

    test("the app's own link from the page's button", () {
      expect(
        parseInvite('homeplay://join?server=https%3A%2F%2Fpc.ts.net&code=ABC'),
        (server: 'https://pc.ts.net', code: 'ABC'),
      );
      expect(parseInvite('homeplay://join?server=javascript%3Aalert(1)&code=ABC'), isNull);
      expect(parseInvite('homeplay://join?code=ABC'), isNull);
    });

    test('anything else is not an invite', () {
      expect(parseInvite('https://pc.ts.net/web/index.html'), isNull);
      expect(parseInvite('hello'), isNull);
      expect(parseInvite(''), isNull);
    });
  });

  test('joining makes an account with the token the server gave', () async {
    late http.Request sent;
    final account = await JellyfinClient.join(
      server: 'https://pc.ts.net',
      code: 'ABC',
      deviceId: 'dev',
      deviceName: 'Pixel',
      client: MockClient((r) async {
        sent = r;
        return http.Response(
            jsonEncode({'ServerName': "Anna's Homeplay", 'UserId': 'u1', 'UserName': 'Petr', 'AccessToken': 'tok'}), 200);
      }),
    );
    expect(sent.url.toString(), 'https://pc.ts.net/Homeplay/Join');
    expect(jsonDecode(sent.body), {'Code': 'ABC', 'DeviceId': 'dev', 'DeviceName': 'Pixel'});
    expect(account.baseUrl, 'https://pc.ts.net');
    expect(account.token, 'tok');
    expect(account.userId, 'u1');
    expect(account.serverName, "Anna's Homeplay");
    expect(account.username, 'Petr');
  });

  test("a used invite says so in the server's words", () async {
    expect(
      () => JellyfinClient.join(
        server: 'https://pc.ts.net',
        code: 'ABC',
        deviceId: 'dev',
        deviceName: 'Pixel',
        client: MockClient((_) async => http.Response('"This invite has been used already. Ask for a new one."', 410)),
      ),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('used already'))),
    );
  });

  test('server messages come out of text, JSON strings and problem objects', () {
    expect(serverMessage('plain'), 'plain');
    expect(serverMessage('"quoted"'), 'quoted');
    expect(serverMessage('{"title":"Bad","detail":"Choose a library"}'), 'Choose a library');
    expect(serverMessage(''), isNull);
  });

  test('photos are not shared unless ticked', () {
    final libs = [for (final l in _libraries) ShareLibrary(l)];
    expect(libs.map((l) => l.sharedByDefault), [true, false]);
  });

  JellyfinClient server(Map<String, dynamic> sharing, {List<http.Request>? seen}) => JellyfinClient(
        _owner,
        'dev',
        client: MockClient((r) async {
          seen?.add(r);
          return switch ((r.method, r.url.path)) {
            ('GET', '/Homeplay/Sharing') => http.Response(jsonEncode(sharing), 200),
            ('DELETE', _) => http.Response('', 204),
            _ => http.Response('', 404),
          };
        }),
      );

  testWidgets('without an internet address the owner is shown how to get one', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ShareScreen(client: server({'PublicUrl': '', 'Libraries': _libraries, 'Invites': []})),
    ));
    await tester.pumpAndSettle();
    expect(find.text('First: your server on the internet'), findsOneWidget);
    expect(find.text('Invite a friend'), findsNothing);
  });

  testWidgets('invites show who joined, and the owner can invite more', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ShareScreen(
        client: server({
          'PublicUrl': 'https://pc.ts.net',
          'Libraries': _libraries,
          'Invites': [
            {
              'Code': 'A',
              'Friend': 'Petr',
              'LibraryNames': ['Movies'],
              'Created': '2026-10-01T10:00:00Z',
              'Expires': '2026-10-08T10:00:00Z',
              'Joined': '2026-10-02T10:00:00Z',
              'State': 'Joined',
              'Link': 'https://pc.ts.net/Homeplay/Join/A',
            },
          ],
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('https://pc.ts.net'), findsOneWidget);
    expect(find.text('Petr'), findsOneWidget);
    expect(find.textContaining('Joined 2.10.2026'), findsOneWidget);
    expect(find.text('Invite a friend'), findsOneWidget);
    await tester.tap(find.text('Invite a friend'));
    await tester.pumpAndSettle();
    expect(find.text('Movies'), findsWidgets);
    expect(find.text('Personal: not shared unless you tick it'), findsOneWidget);
  });
}
