import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/accounts_screen.dart';
import 'package:homeplay/services/app_log.dart';
import 'package:homeplay/services/artwork_cache.dart';
import 'package:homeplay/services/connection.dart';
import 'package:homeplay/services/problem_report.dart';
import 'package:homeplay/widgets/error_view.dart';
import 'package:http/http.dart' as http;

const _token = '0123456789abcdef0123456789abcdef';

void main() {
  group('connection errors', () {
    test('airplane mode is told apart from a server that does not answer', () {
      const unreachable = SocketException('Connection failed',
          osError: OSError('Network is unreachable', 101), address: null);
      expect(netProblem(unreachable), NetProblem.offline);
      expect(netProblem(http.ClientException('Failed host lookup: nas.local')), NetProblem.unreachable);
      expect(netProblem(http.ClientException('Failed host lookup: nas.local'), offline: true), NetProblem.offline);
      expect(netProblem(TimeoutException('slow')), NetProblem.timeout);
      expect(netProblem(TimeoutException('slow'), offline: true), NetProblem.offline);
      expect(netProblem(ApiException('Wrong username or password')), isNull);
    });

    test('each problem has a plain message, and others pass without secrets', () {
      expect(errorMessage(TimeoutException('x'), offline: true), contains('Downloads'));
      expect(errorMessage(http.ClientException('Connection refused')), startsWith('Cannot reach the server'));
      expect(errorMessage(TimeoutException('x')), startsWith('The server did not answer in time'));
      expect(errorMessage(ApiException('Server answered 500 for /Items')), 'Server answered 500 for /Items');
      expect(errorMessage(Exception('bad http://h/a?api_key=$_token')), isNot(contains(_token)));
    });

    test('only "none" means no network; a VPN alone counts', () {
      expect(isOfflineResult([ConnectivityResult.none]), isTrue);
      expect(isOfflineResult([ConnectivityResult.vpn]), isFalse);
      expect(isOfflineResult([ConnectivityResult.wifi, ConnectivityResult.vpn]), isFalse);
      expect(isOfflineResult([]), isFalse);
    });

    test('without a network the app stays on the server list', () {
      const a = Account(id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://h', username: 'u', serverName: 'S');
      expect(pickStartAccount([a], 'a'), a);
      expect(pickStartAccount([a], 'a', offline: true), isNull);
    });

    testWidgets('a connection error offers Downloads, a refusal does not', (tester) async {
      Future<void> show(Object error) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: ErrorView(error: error, onRetry: () {}))));
      await show(http.ClientException('Connection refused'));
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);
      await show(ApiException('Session expired'));
      expect(find.text('Session expired'), findsOneWidget);
      expect(find.text('Downloads'), findsNothing);
    });
  });

  group('secrets in logs', () {
    test('links with a token go whole, other links lose their query', () {
      expect(redactSecrets('GET http://192.168.1.5:8096/Items/1/Images/Primary?api_key=abc&tag=x done'),
          'GET [link removed] done');
      expect(redactSecrets('http://nas:4533/rest/getCoverArt?u=anna&t=abc&s=salt&id=1'), '[link removed]');
      expect(redactSecrets('https://user:pw@nas/x'), '[link removed]');
      expect(redactSecrets('see https://ownmedia.app/join.html?ref=1#s=x'), 'see https://ownmedia.app/join.html');
      expect(redactSecrets('plain https://ownmedia.app/version.json'), 'plain https://ownmedia.app/version.json');
    });

    test('token fields, bearer tokens and long hex runs are hidden', () {
      expect(redactSecrets('MediaBrowser Client="OwnMedia", Token="secret1"'),
          'MediaBrowser Client="OwnMedia", Token="[hidden]"');
      expect(redactSecrets('{"AccessToken":"secret2","User":{}}'), '{"AccessToken":"[hidden]","User":{}}');
      expect(redactSecrets('password: hunter2'), 'password: [hidden]');
      expect(redactSecrets('Authorization: Bearer abc.def'), 'Authorization: Bearer [hidden]');
      expect(redactSecrets('item $_token played'), 'item [hidden] played');
      expect(redactSecrets('Wrong username or password'), 'Wrong username or password');
    });

    test('log lines get the time, lose secrets and blank lines, and are cut', () {
      final at = DateTime(2026, 10, 31, 9, 5, 7);
      expect(logLines('homeplay a\n\nToken="x"', at), ['09:05:07 homeplay a', '09:05:07 Token="[hidden]"']);
      final long = logLines('y' * 50, at, maxLength: 10).single;
      expect(long, '09:05:07 ${'y' * 10}…');
    });

    test('the in-memory log keeps only the last lines', () {
      AppLog.clear();
      for (var i = 0; i < AppLog.maxLines + 5; i++) {
        AppLog.add('line $i', at: DateTime(2026));
      }
      expect(AppLog.lines, hasLength(AppLog.maxLines));
      expect(AppLog.lines.first, endsWith('line 5'));
      AppLog.clear();
    });
  });

  group('problem report', () {
    const facts = (app: 'OwnMedia 0.3.18 (2022)', phone: 'Google Pixel 10a', system: 'Android 16 (SDK 36)');

    test('has the version, the phone and the system, and a log only when asked', () {
      final plain = problemReport(facts);
      expect(plain.subject, 'OwnMedia problem (OwnMedia 0.3.18 (2022))');
      expect(plain.body, contains('App: OwnMedia 0.3.18 (2022)'));
      expect(plain.body, contains('Phone: Google Pixel 10a'));
      expect(plain.body, contains('System: Android 16 (SDK 36)'));
      expect(plain.body, isNot(contains('Recent app events')));

      final withLog = problemReport(facts, log: ['10:00:00 homeplay x', '10:00:01 url http://h/a?api_key=k']);
      expect(withLog.body, contains('Recent app events'));
      expect(withLog.body, contains('10:00:00 homeplay x'));
      expect(withLog.body, contains('10:00:01 url [link removed]'));
      expect(problemReport(facts, log: []).body, contains('(none)'));
    });

    test('the support address is right and not written out whole in the code', () {
      expect(supportAddress, 'support@ownmedia.app');
      final whole = ['support', 'ownmedia.app'].join('@');
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        expect(f.readAsStringSync().contains(whole), isFalse, reason: f.path);
      }
    });
  });

  group('artwork cache', () {
    test('the file name ignores the sign-in and the order of parameters', () {
      final a = artworkCacheName(Uri.parse('http://nas:4533/rest/getCoverArt?u=anna&t=aaa&s=bbb&id=7&size=300'));
      final b = artworkCacheName(Uri.parse('http://nas:4533/rest/getCoverArt?size=300&id=7&t=ccc&s=ddd&u=anna'));
      final other = artworkCacheName(Uri.parse('http://nas:4533/rest/getCoverArt?u=anna&t=aaa&s=bbb&id=8&size=300'));
      expect(a, b);
      expect(a, isNot(other));
      expect(a, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(artworkCacheName(Uri.parse('http://h/Items/1/Images/Primary?api_key=x&tag=1')),
          artworkCacheName(Uri.parse('http://h/Items/1/Images/Primary?tag=1')));
    });

    test('the longest unused files go once the folder is too big', () {
      final files = [
        (path: 'old', size: 40, used: DateTime(2026, 1)),
        (path: 'new', size: 40, used: DateTime(2026, 3)),
        (path: 'mid', size: 40, used: DateTime(2026, 2)),
      ];
      expect(artworkToPrune(files, 100), ['old']);
      expect(artworkToPrune(files, 120), isEmpty);
      expect(artworkToPrune(files, 30), ['new', 'mid', 'old']);
    });

    test('a picture never shows its address, and the same address is the same picture', () {
      final url = Uri.parse('http://nas:4533/rest/getCoverArt?t=$_token&id=1');
      final p = CachedArtwork(url, headers: const {'Authorization': 'x'});
      expect(p.toString(), isNot(contains('nas')));
      expect(p.toString(), isNot(contains(_token)));
      expect(p, CachedArtwork(url));
      expect(ArtworkUnavailable('timeout').toString(), isNot(contains('http')));
    });
  });
}
