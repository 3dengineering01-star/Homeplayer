import 'package:http/http.dart' as http;

import '../models/account.dart';

/// Whether a server answers at all, asked without signing in: Jellyfin's public info, or a
/// Subsonic ping (which answers even without credentials, with an error inside).
Future<bool> serverAnswers(Account a, {http.Client? client, Duration timeout = const Duration(seconds: 4)}) async {
  final path = switch (a.kind) {
    ServerKind.jellyfin => '/System/Info/Public',
    ServerKind.subsonic => '/rest/ping.view',
  };
  final c = client ?? http.Client();
  try {
    final res = await c.get(Uri.parse('${a.baseUrl}$path').replace(queryParameters: {
      if (a.kind == ServerKind.subsonic) 'f': 'json',
    })).timeout(timeout);
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    if (client == null) c.close();
  }
}

/// "Good morning" and so on, for the top of the server list.
String greeting(DateTime now) => switch (now.hour) {
      >= 5 && < 12 => 'Good morning',
      >= 12 && < 18 => 'Good afternoon',
      >= 18 && < 23 => 'Good evening',
      _ => 'Good night',
    };
