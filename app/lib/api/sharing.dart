import 'dart:convert';

/// Sharing a server with friends, as the Homeplay plugin (1.3+) keeps it: the server's internet
/// address, the libraries there are and the invites the owner made.

class ShareLibrary {
  ShareLibrary(Map<String, dynamic> j)
      : id = j['Id'] as String,
        name = j['Name'] as String? ?? '',
        collectionType = j['CollectionType'] as String?;

  final String id;
  final String name;
  final String? collectionType;

  /// Shared unless the owner unticks it; photos are private by default.
  bool get sharedByDefault => collectionType != 'homevideos' && collectionType != 'photos';
}

enum InviteState { waiting, joined, expired }

class ShareInvite {
  ShareInvite(Map<String, dynamic> j)
      : code = j['Code'] as String,
        friend = j['Friend'] as String? ?? '',
        libraryNames = [for (final n in j['LibraryNames'] as List? ?? const []) n as String],
        expires = DateTime.parse(j['Expires'] as String).toLocal(),
        joined = j['Joined'] == null ? null : DateTime.parse(j['Joined'] as String).toLocal(),
        state = switch (j['State']) {
          'Joined' => InviteState.joined,
          'Expired' => InviteState.expired,
          _ => InviteState.waiting,
        },
        link = j['Link'] as String? ?? '',
        device = j['Device'] as String? ?? '',
        lastSeen = j['LastSeen'] == null ? null : DateTime.parse(j['LastSeen'] as String).toLocal(),
        watching = j['Watching'] as String?;

  final String code;
  final String friend;
  final List<String> libraryNames;
  final DateTime expires;
  final DateTime? joined;
  final InviteState state;
  final String link;

  /// The phone that joined, as it calls itself ("Google Pixel 10a"); empty before plugin 1.7.
  final String device;

  /// When the friend last used the server; null if never or before plugin 1.7.
  final DateTime? lastSeen;

  /// What plays for the friend right now.
  final String? watching;
}

/// "today 14:05", "yesterday 09:30" or "12.10.2026" for when a friend was last seen.
String seenLabel(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day), today = DateTime(now.year, now.month, now.day);
  final time = '${at.hour}:${at.minute.toString().padLeft(2, '0')}';
  return switch (today.difference(day).inDays) {
    0 => 'today $time',
    1 => 'yesterday $time',
    _ => '${at.day}.${at.month.toString().padLeft(2, '0')}.${at.year}',
  };
}

class SharingInfo {
  SharingInfo(Map<String, dynamic> j)
      : publicUrl = j['PublicUrl'] as String? ?? '',
        libraries = [for (final l in j['Libraries'] as List? ?? const []) ShareLibrary(l as Map<String, dynamic>)],
        invites = [for (final i in j['Invites'] as List? ?? const []) ShareInvite(i as Map<String, dynamic>)];

  SharingInfo._(this.publicUrl, this.libraries, this.invites);

  final String publicUrl;
  final List<ShareLibrary> libraries;

  /// Oldest first, as the server keeps them.
  final List<ShareInvite> invites;

  /// The same with [invite] added as the newest, or put in place of the one with its code.
  SharingInfo withInvite(ShareInvite invite) => SharingInfo._(publicUrl, libraries, [
        for (final i in invites)
          if (i.code != invite.code) i,
        invite,
      ]);

  /// The same without the invite [code].
  SharingInfo withoutInvite(String code) =>
      SharingInfo._(publicUrl, libraries, [for (final i in invites) if (i.code != code) i]);
}

/// The server's own words from an error answer: plain text, a JSON string or a problem object.
String? serverMessage(String body) {
  final text = body.trim();
  if (text.isEmpty) return null;
  try {
    final j = jsonDecode(text);
    if (j is String) return j;
    if (j is Map) return (j['detail'] ?? j['title'])?.toString();
  } on FormatException {
    // Plain text.
  }
  return text.length > 300 ? null : text;
}
