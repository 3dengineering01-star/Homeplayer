/// An invite to a friend's server: where it is and the one-time code.
typedef InviteLink = ({String server, String code});

final _webLink = RegExp(r'(https?://\S+?)/homeplay/join/([A-Za-z0-9]+)', caseSensitive: false);
final _appLink = RegExp(r'homeplay://join\?\S+', caseSensitive: false);
final _siteLink = RegExp(r'https://(?:www\.)?ownmedia\.app/join(?:\.html)?/?#(\S+)', caseSensitive: false);

/// The invite in [text]: the app's own link (homeplay://join?server=…&code=…), the website's page
/// (https://ownmedia.app/join.html#s=…&c=…) or the server's page (https://…/Homeplay/Join/CODE),
/// alone or inside a message. Null when there is none.
InviteLink? parseInvite(String text) {
  final site = _siteLink.firstMatch(text);
  if (site != null) {
    try {
      final fields = Uri.splitQueryString(site.group(1)!);
      final server = fields['s'];
      final code = fields['c'];
      if (server != null && code != null && _code.hasMatch(code) && _isSite(server)) {
        return (server: _trimSlash(server), code: code);
      }
    } on Object {
      // A broken escape in a copied link: not an invite.
    }
  }
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

final _code = RegExp(r'^[A-Za-z0-9]{1,64}$');

bool _isSite(String s) {
  final uri = Uri.tryParse(s);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
}

String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// What a friend receives: who shares, and the link to open on the phone.
String inviteMessage(String serverName, String link) =>
    '$serverName: I share my movies and music with you in OwnMedia. '
    'Open this link on your phone: $link';

/// The server's internet address as typed, made into a site address: https:// added when
/// missing, no trailing slash. Null when it is not one (empty, no dot in the name).
String? normalizeAddress(String typed) {
  var text = typed.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || !uri.host.contains('.')) return null;
  return _trimSlash('${uri.scheme}://${uri.authority}${uri.path}');
}
