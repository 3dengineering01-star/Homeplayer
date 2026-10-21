import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/app_update.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _app({String build = '2017', String? store}) => PackageInfo.setMockInitialValues(
    appName: 'OwnMedia', packageName: 'dev.homeplay.homeplay', version: '0.3.13', buildNumber: build, buildSignature: '', installerStore: store);

http.Client _site(Map<String, dynamic> body, List<Uri> asked) => MockClient((r) async {
      asked.add(r.url);
      return http.Response(jsonEncode(body), 200);
    });

const _newer = {'version': '0.3.14', 'build': 2018, 'apk': 'OwnMedia.apk', 'notes': 'Lyrics from LRCLIB'};

void main() {
  test('the website file: version, build, the app file next to it; nothing else counts', () {
    final u = parseUpdate(_newer, updateUrl)!;
    expect(u.version, '0.3.14');
    expect(u.build, 2018);
    expect(u.apk.toString(), 'https://ownmedia.app/download/OwnMedia.apk');
    expect(u.notes, 'Lyrics from LRCLIB');
    expect(parseUpdate({'version': '1', 'build': '2018', 'apk': 'a.apk'}, updateUrl), isNull);
    expect(parseUpdate({'version': '1', 'build': 2018, 'apk': 'http://elsewhere/a.apk'}, updateUrl), isNull,
        reason: 'only a secure download');
    expect(parseUpdate('nonsense', updateUrl), isNull);
  });

  test('offered when newer and not put off, or when asked', () {
    final u = parseUpdate(_newer, updateUrl);
    expect(shouldOffer(u, localBuild: 2017), isTrue);
    expect(shouldOffer(u, localBuild: 2018), isFalse);
    expect(shouldOffer(u, localBuild: 2017, skipped: 2018), isFalse);
    expect(shouldOffer(u, localBuild: 2017, skipped: 2018, asked: true), isTrue);
    expect(shouldOffer(null, localBuild: 1), isFalse);
  });

  test('once a day at most, not when turned off, never for an app from Google Play', () async {
    SharedPreferences.setMockInitialValues({});
    _app();
    final asked = <Uri>[];
    expect((await AppUpdate.check(client: _site(_newer, asked)))?.version, '0.3.14');
    expect(asked.single, updateUrl);
    // The same day: no second request.
    expect(await AppUpdate.check(client: _site(_newer, asked)), isNull);
    expect(asked, hasLength(1));
    // "Check now" still asks.
    expect(await AppUpdate.check(asked: true, client: _site(_newer, asked)), isNotNull);

    SharedPreferences.setMockInitialValues({'update_check': false});
    asked.clear();
    expect(await AppUpdate.check(client: _site(_newer, asked)), isNull);
    expect(asked, isEmpty);

    SharedPreferences.setMockInitialValues({});
    _app(store: 'com.android.vending');
    expect(await AppUpdate.check(asked: true, client: _site(_newer, asked)), isNull);
    expect(asked, isEmpty);
  });
}
