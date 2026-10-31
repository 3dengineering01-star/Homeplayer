import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/common.dart';
import 'app_log.dart';
import 'device_name.dart';

/// Where problem reports go. Put together here rather than written out whole, so the address
/// is not lifted from the app's files by spam collectors.
String get supportAddress => ['support', ['ownmedia', 'app'].join('.')].join('@');

/// The facts a problem report starts with.
typedef ReportFacts = ({String app, String phone, String system});

/// What the person writes to support: room for their own words, then the app's version, the
/// phone and its system, and when they chose so, the app's recent events. The log is cleaned
/// of secrets once more here, in case a line got past the first time.
({String subject, String body}) problemReport(ReportFacts facts, {List<String>? log}) {
  final b = StringBuffer()
    ..writeln('What happened, and what did you expect?')
    ..writeln()
    ..writeln()
    ..writeln()
    ..writeln('---')
    ..writeln('App: ${facts.app}')
    ..writeln('Phone: ${facts.phone}')
    ..writeln('System: ${facts.system}');
  if (log != null) {
    b
      ..writeln()
      ..writeln('Recent app events (without passwords, tokens or links that carry them):');
    if (log.isEmpty) b.writeln('(none)');
    for (final line in log) {
      b.writeln(redactSecrets(line));
    }
  }
  return (subject: 'OwnMedia problem (${facts.app})', body: b.toString());
}

/// This app and phone, for [problemReport]. Asks only the phone, never the network.
Future<ReportFacts> reportFacts() async {
  var app = 'OwnMedia';
  try {
    final info = await PackageInfo.fromPlatform();
    app = 'OwnMedia ${info.version} (${info.buildNumber})';
  } catch (_) {}
  var system = Platform.operatingSystem;
  try {
    if (Platform.isAndroid) {
      final v = (await DeviceInfoPlugin().androidInfo).version;
      system = 'Android ${v.release} (SDK ${v.sdkInt})';
    } else if (Platform.isIOS) {
      system = 'iOS ${(await DeviceInfoPlugin().iosInfo).systemVersion}';
    }
  } catch (_) {}
  return (app: app, phone: await deviceName(), system: system);
}

/// The report with the log as it is now, when [withLog].
Future<({String subject, String body})> currentReport({required bool withLog}) async =>
    problemReport(await reportFacts(), log: withLog ? AppLog.lines : null);
