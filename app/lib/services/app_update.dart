import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_links.dart';

/// Where the website says which version of the Android app is the newest. publish-app.cmd
/// writes this file next to OwnMedia.apk.
final updateUrl = Uri.parse('https://ownmedia.app/download/version.json');

/// A version of the app on the website.
class AppUpdateInfo {
  const AppUpdateInfo({required this.version, required this.build, required this.apk, this.notes});

  /// As people read it: "0.3.14".
  final String version;

  /// The number Android compares: higher is newer.
  final int build;

  /// The app file to download.
  final Uri apk;

  /// What is new, in a few words; may be missing.
  final String? notes;
}

/// The website's version.json ({"version": "0.3.14", "build": 2018, "apk": "OwnMedia.apk",
/// "notes": "..."}), with the file's address taken relative to [from]. Null for anything else.
AppUpdateInfo? parseUpdate(Object? json, Uri from) {
  if (json is! Map) return null;
  final version = json['version'], build = json['build'], apk = json['apk'];
  if (version is! String || build is! int || apk is! String || apk.isEmpty) return null;
  final url = from.resolve(apk);
  if (url.scheme != 'https') return null;
  final notes = json['notes'];
  return AppUpdateInfo(version: version, build: build, apk: url, notes: notes is String && notes.trim().isNotEmpty ? notes.trim() : null);
}

/// Whether to tell about [remote]: newer than this app's [localBuild], and not the version the
/// person already said "Later" to ([skipped]), unless they asked themselves ([asked]).
bool shouldOffer(AppUpdateInfo? remote, {required int localBuild, int? skipped, bool asked = false}) =>
    remote != null && remote.build > localBuild && (asked || remote.build != skipped);

/// Looks on the website for a newer Android app, at most once a day. Not for an app from Google
/// Play, which updates it itself, and not on iPhone.
class AppUpdate {
  AppUpdate._();

  static const _enabledKey = 'update_check';
  static const _lastKey = 'update_last_check';
  static const _skipKey = 'update_skipped_build';

  static Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? true;

  static Future<void> setEnabled(bool on) async => (await SharedPreferences.getInstance()).setBool(_enabledKey, on);

  /// Not asked again about this version; a newer one is offered again.
  static Future<void> skip(int build) async => (await SharedPreferences.getInstance()).setInt(_skipKey, build);

  /// Whether this app can update itself from the website at all.
  static Future<bool> available() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final info = await PackageInfo.fromPlatform();
    return info.installerStore != 'com.android.vending';
  }

  /// The newer version on the website, or null. [asked]: the person pressed "Check now", so the
  /// daily limit, the switch in the settings and "Later" do not count. Throws only when asked.
  static Future<AppUpdateInfo?> check({bool asked = false, http.Client? client}) async {
    if (!await available()) return null;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!asked) {
      if (!(prefs.getBool(_enabledKey) ?? true)) return null;
      final last = prefs.getInt(_lastKey) ?? 0;
      if (now - last < const Duration(hours: 20).inMilliseconds) return null;
    }
    try {
      final res = await (client ?? http.Client()).get(updateUrl).timeout(const Duration(seconds: 10));
      await prefs.setInt(_lastKey, now);
      if (res.statusCode != 200) throw Exception('the website answered ${res.statusCode}');
      final remote = parseUpdate(jsonDecode(res.body), updateUrl);
      final local = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      return shouldOffer(remote, localBuild: local, skipped: prefs.getInt(_skipKey), asked: asked) ? remote : null;
    } catch (e) {
      debugPrint('homeplay update check failed: $e');
      if (asked) rethrow;
      return null;
    }
  }
}

/// "OwnMedia 0.3.14 is available": Download opens the file in the browser, which then offers
/// to install it over this one (settings and servers stay).
Future<void> offerUpdate(BuildContext context, AppUpdateInfo u) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final download = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.system_update),
      title: Text('OwnMedia ${u.version} is available'),
      content: Text([
        if (u.notes != null) u.notes!,
        'It downloads in the browser; open the file and install it over this one. Your servers and settings stay.',
      ].join('\n\n')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Download')),
      ],
    ),
  );
  if (download == true) {
    if (!await AppLinks.view(u.apk.toString())) {
      messenger?.showSnackBar(SnackBar(content: Text('No browser to download it. The address: ${u.apk}')));
    }
  } else if (download == false) {
    await AppUpdate.skip(u.build);
  }
}
