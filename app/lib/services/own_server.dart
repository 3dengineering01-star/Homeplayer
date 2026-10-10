import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/account.dart';

/// Where a Homeplay server gives out its own installer for Windows (plugin 1.4 and later).
String setupLink(String server) => '${server.endsWith('/') ? server.substring(0, server.length - 1) : server}/Homeplay/Setup';

/// Whether to show how to make a server of one's own: every server on this phone is someone
/// else's, added from an invite.
bool needsOwnServer(List<Account> accounts) => accounts.isNotEmpty && accounts.every((a) => a.shared);

/// The servers to ask for the installer: the friends' ones on this phone.
List<String> sharedServers(List<Account> accounts) =>
    [for (final a in accounts) if (a.shared && a.kind == ServerKind.jellyfin) a.baseUrl];

/// What goes to one's own computer: the installer's link and what to do with it.
String setupMessage(String link) => 'Homeplay server for Windows. Open this on your computer, download and run it: $link';

/// The installer's link on the first of [servers] that gives it out; null when none does
/// (an older server, or none answers). Only the answer's headers are read, not the file.
Future<String?> findSetupLink(List<String> servers, {http.Client Function()? client}) async {
  for (final server in servers) {
    final link = setupLink(server);
    final c = client?.call() ?? http.Client();
    try {
      final res = await c.send(http.Request('GET', Uri.parse(link))).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return link;
    } catch (e) {
      debugPrint('homeplay setup link: ${e.runtimeType}');
    } finally {
      c.close();
    }
  }
  return null;
}
