import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import 'invite_link.dart';

/// The invite in [clipboard] to offer without being asked, or null: there is none, its server is
/// on this phone already, or it was offered before ([offered] codes).
InviteLink? inviteToOffer(String? clipboard, List<Account> accounts, Iterable<String> offered) {
  if (clipboard == null || clipboard.isEmpty) return null;
  final invite = parseInvite(clipboard);
  if (invite == null || offered.contains(invite.code)) return null;
  final server = _site(invite.server);
  if (accounts.any((a) => _site(a.baseUrl) == server)) return null;
  return invite;
}

String _site(String url) {
  var s = url.trim().toLowerCase();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// A friend who installs the app from an invite does not have to open the invite again: the
/// website's invite page copies it when the app is downloaded, and the app picks it up when it
/// opens with no servers yet. Each invite is offered once.
class InviteInbox {
  InviteInbox._();

  static const _key = 'invite.offered';

  /// The invite waiting on the clipboard, once; null when there is none.
  static Future<InviteLink?> fromClipboard(List<Account> accounts) async {
    try {
      // Asking whether there is text does not read it (no "pasted" notice on the phone).
      if (!await Clipboard.hasStrings()) return null;
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      final prefs = await SharedPreferences.getInstance();
      final invite = inviteToOffer(text, accounts, prefs.getStringList(_key) ?? const []);
      if (invite != null) await markOffered(invite.code);
      return invite;
    } catch (e) {
      debugPrint('homeplay invite clipboard: $e');
      return null;
    }
  }

  /// Not to offer the invite with [code] again: it is open already.
  static Future<void> markOffered(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final offered = prefs.getStringList(_key) ?? const <String>[];
    if (offered.contains(code)) return;
    // The last few are enough: an invite works once.
    await prefs.setStringList(_key, [...offered.skip(offered.length > 19 ? offered.length - 19 : 0), code]);
  }
}
