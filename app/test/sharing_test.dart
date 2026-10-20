import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/api/sharing.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/share_screen.dart';
import 'package:homeplay/services/invite_inbox.dart';
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

    test("the website's invite page carries the server and the code after #", () {
      expect(
        parseInvite('https://ownmedia.app/join.html#s=https%3A%2F%2Fpc.ts.net%2F&n=Anna%27s%20%D0%BA%D0%B8%D0%BD%D0%BE&c=ABC'),
        (server: 'https://pc.ts.net', code: 'ABC'),
      );
      expect(
        parseInvite(inviteMessage('Anna', 'https://ownmedia.app/join.html#s=http%3A%2F%2F192.168.1.10%3A8096&c=Q7')),
        (server: 'http://192.168.1.10:8096', code: 'Q7'),
      );
      expect(parseInvite('https://ownmedia.app/join#s=https%3A%2F%2Fpc.ts.net&c=Z9'), (server: 'https://pc.ts.net', code: 'Z9'));
      // Cut short when copied, or not a site: not an invite.
      expect(parseInvite('https://ownmedia.app/join.html#s=https%3A%2F%2Fpc.ts.net'), isNull);
      expect(parseInvite('https://ownmedia.app/join.html#s=javascript%3Aalert(1)&c=ABC'), isNull);
      expect(parseInvite('https://ownmedia.app/join.html#s=https%3A%2F%2Fpc.ts.net&c=A%2FB'), isNull);
      expect(parseInvite('https://ownmedia.app/join.html#s=%E0%A4%A&c=ABC'), isNull);
    });

    test('an invite on the clipboard is offered once, and not for a server already added', () {
      const link = 'https://ownmedia.app/join.html#s=https%3A%2F%2Fpc.ts.net&c=ABC';
      const added = Account(id: 'a', kind: ServerKind.jellyfin, baseUrl: 'https://PC.ts.net/', username: 'u', serverName: 'PC');
      expect(inviteToOffer('Anna: open this on your phone: $link', [], []), (server: 'https://pc.ts.net', code: 'ABC'));
      expect(inviteToOffer(link, [], ['ABC']), isNull);
      expect(inviteToOffer(link, [added], []), isNull);
      expect(inviteToOffer('a shopping list', [], []), isNull);
      expect(inviteToOffer(null, [], []), isNull);
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
    expect(account.shared, isTrue);
    expect(Account.fromJson(account.toJson()).shared, isTrue);
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

  test('the internet address as typed becomes a site address', () {
    expect(normalizeAddress('goodman.tail1234.ts.net'), 'https://goodman.tail1234.ts.net');
    expect(normalizeAddress(' https://goodman.tail1234.ts.net/ '), 'https://goodman.tail1234.ts.net');
    expect(normalizeAddress('http://192.168.1.108:8096'), 'http://192.168.1.108:8096');
    expect(normalizeAddress(''), isNull);
    expect(normalizeAddress('goodman'), isNull);
    expect(normalizeAddress('ftp://x.y'), isNull);
  });

  test('server messages come out of text, JSON strings and problem objects', () {
    expect(serverMessage('plain'), 'plain');
    expect(serverMessage('"quoted"'), 'quoted');
    expect(serverMessage('{"title":"Bad","detail":"Choose a library"}'), 'Choose a library');
    expect(serverMessage(''), isNull);
    // Module 1.10 refuses a home address with a whole sentence: the owner sees it as it is.
    const homeOnly = 'This address works only at home. Friends need the internet address, '
        'like https://your-pc.tail1234.ts.net (Tailscale Funnel).';
    expect(serverMessage('"$homeOnly"'), homeOnly);
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
    expect(find.textContaining('run OwnMediaSetup again'), findsOneWidget);
    expect(find.textContaining('tailscale funnel'), findsNothing);
    expect(find.text('Invite a friend'), findsNothing);
  });

  testWidgets('an empty address is not saved: the example is only an example', (tester) async {
    final seen = <http.Request>[];
    await tester.pumpWidget(MaterialApp(
      home: ShareScreen(client: server({'PublicUrl': '', 'Libraries': _libraries, 'Invites': []}, seen: seen)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I have an address already'));
    await tester.pumpAndSettle();
    expect(find.text('For example https://goodman.tail1234.ts.net'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Type the address Tailscale showed'), findsOneWidget);
    expect(seen.where((r) => r.method == 'POST'), isEmpty);
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

  testWidgets('who has access: the phone, what they watch, and ending the access', (tester) async {
    final seen = <http.Request>[];
    Map<String, dynamic> joined(String code, String friend, {String? watching, String? lastSeen}) => {
          'Code': code,
          'Friend': friend,
          'LibraryNames': ['Movies'],
          'Created': '2026-10-01T10:00:00Z',
          'Expires': '2026-10-08T10:00:00Z',
          'Joined': '2026-10-02T10:00:00Z',
          'State': 'Joined',
          'Link': '',
          'Device': 'Google Pixel 10a',
          'LastSeen': ?lastSeen,
          'Watching': ?watching,
        };
    await tester.pumpWidget(MaterialApp(
      home: ShareScreen(
        client: server({
          'PublicUrl': 'https://pc.ts.net',
          'Libraries': _libraries,
          'Invites': [
            joined('A', 'Petr', watching: 'Dune'),
            joined('B', 'Olga', lastSeen: '2026-10-05T08:30:00Z'),
            {
              'Code': 'C',
              'Friend': 'Ivan',
              'LibraryNames': ['Movies'],
              'Created': '2026-10-01T10:00:00Z',
              'Expires': '2099-10-08T10:00:00Z',
              'State': 'Waiting',
              'Link': 'https://pc.ts.net/Homeplay/Join/C',
            },
          ],
        }, seen: seen),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Who has access (2)'), findsOneWidget);
    expect(find.text('Invites not used'), findsOneWidget);
    expect(find.textContaining('Joined 2.10.2026 from Google Pixel 10a'), findsNWidgets(2));
    expect(find.textContaining('Watching now: Dune'), findsOneWidget);
    expect(find.textContaining('Last seen 5.10.2026'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('End access').last); // Newest first: Petr's invite is the oldest.
    await tester.pumpAndSettle();
    expect(find.text("End Petr's access?"), findsOneWidget);
    expect(find.textContaining('The Google Pixel 10a that joined'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(seen.where((r) => r.method == 'DELETE').single.url.path, '/Homeplay/Invites/A');
  });

  test('when the last time seen was', () {
    final now = DateTime(2026, 10, 17, 20, 0);
    expect(seenLabel(DateTime(2026, 10, 17, 9, 5), now), 'today 9:05');
    expect(seenLabel(DateTime(2026, 10, 16, 23, 59), now), 'yesterday 23:59');
    expect(seenLabel(DateTime(2026, 10, 2, 12, 0), now), '2.10.2026');
  });

  test('a friend whose access was ended is told so, the owner of a server is not', () async {
    // Jellyfin 12.1 answers 403 to a friend whose user the owner removed, 401 to an expired sign-in.
    JellyfinClient signedOut(Account a, int status) =>
        JellyfinClient(a, 'dev', client: MockClient((_) async => http.Response('', status)));
    const friend = Account(
        id: 'f', kind: ServerKind.jellyfin, baseUrl: 'https://pc.ts.net', username: 'Petr', serverName: "Anna's", token: 't', userId: 'u', shared: true);
    await expectLater(signedOut(friend, 403).views(), throwsA(predicate((e) => '$e'.contains('ended your access'))));
    await expectLater(signedOut(_owner, 401).views(), throwsA(predicate((e) => '$e'.contains('Session expired'))));
  });

  testWidgets('a removed invite goes at once, even while the server is slow or answers with the old list',
      (tester) async {
    final sharing = {
      'PublicUrl': 'https://pc.ts.net',
      'Libraries': _libraries,
      'Invites': [
        {
          'Code': 'C',
          'Friend': 'Ivan',
          'LibraryNames': ['Movies'],
          'Created': '2026-10-01T10:00:00Z',
          'Expires': '2099-10-08T10:00:00Z',
          'State': 'Waiting',
          'Link': 'https://pc.ts.net/Homeplay/Join/C',
        },
      ],
    };
    final client = JellyfinClient(
      _owner,
      'dev',
      client: MockClient((r) async {
        if (r.method == 'DELETE') {
          // The server takes its time.
          await Future<void>(() => null);
          return http.Response('', 204);
        }
        return http.Response(jsonEncode(sharing), 200); // Never forgets: the old list.
      }),
    );
    await tester.pumpWidget(MaterialApp(home: ShareScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Ivan'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();
    expect(find.text('Ivan'), findsNothing, reason: 'gone before the server answers');
    await tester.pumpAndSettle();
    expect(find.text('Ivan'), findsNothing, reason: 'an old list from the server does not bring it back');
  });

  testWidgets('a new invite shows its link at once, to send or copy, and is in the list', (tester) async {
    final sharing = {'PublicUrl': 'https://pc.ts.net', 'Libraries': _libraries, 'Invites': <Object>[]};
    final client = JellyfinClient(
      _owner,
      'dev',
      client: MockClient((r) async => switch ((r.method, r.url.path)) {
            ('POST', '/Homeplay/Invites') => http.Response(
                jsonEncode({
                  'Code': 'N',
                  'Friend': 'Olga',
                  'LibraryNames': ['Movies'],
                  'Created': '2026-10-19T10:00:00.0000000Z',
                  'Expires': '2026-10-26T10:00:00.0000000Z',
                  'State': 'Waiting',
                  'Link': 'https://pc.ts.net/Homeplay/Join/N',
                }),
                200),
            _ => http.Response(jsonEncode(sharing), 200), // Slow to learn of the new one.
          }),
    );
    await tester.pumpWidget(MaterialApp(home: ShareScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite a friend').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Olga');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make the link'));
    await tester.pumpAndSettle();
    expect(find.text('The link for Olga is ready'), findsOneWidget);
    expect(find.text('https://pc.ts.net/Homeplay/Join/N'), findsOneWidget);
    expect(find.text('Send the link'), findsOneWidget);
    expect(find.text('Copy the link'), findsOneWidget);
    await tester.tap(find.text('Copy the link'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Link copied'), findsOneWidget);
    expect(find.text('Olga'), findsOneWidget, reason: 'in the list, though the server list did not have it yet');
    expect(tester.takeException(), isNull);
  });
}
