/// An invite to a friend's server: where it is and the one-time code.
typedef InviteLink = ({String server, String code});

final _webLink = RegExp(r'(https?://\S+?)/homeplay/join/([A-Za-z0-9]+)', caseSensitive: false);
final _appLink = RegExp(r'homeplay://join\?\S+', caseSensitive: false);

/// The invite in [text]: the app's own link (homeplay://join?server=…&code=…) or the page's
/// address (https://…/Homeplay/Join/CODE), alone or inside a message. Null when there is none.
InviteLink? parseInvite(String text) {
  final app = _appLink.firstMatch(text);
  if (app != null) {
    final uri = Uri.tryParse(app.group(0)!);
    final server = uri?.queryParameters['server'];
    final code = uri?.queryParameters['code'];
    if (server != null && code != null && code.isNotEmpty && _isSite(server)) {
      return (server: _trimSlash(server), code: code);
    }
  }
  final web = _webLink.firstMatch(text);
  if (web != null && _isSite(web.group(1)!)) return (server: _trimSlash(web.group(1)!), code: web.group(2)!);
  return null;
}

bool _isSite(String s) {
  final uri = Uri.tryParse(s);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
}

String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// What a friend receives: who shares, and the link to open on the phone.
String inviteMessage(String serverName, String link) =>
    '$serverName: I share my movies and music with you in Homeplay. '
    'Open this link on your Android phone: $link';
