enum ServerKind { jellyfin, subsonic }

/// A saved connection to one server. Passwords are never stored:
/// Jellyfin keeps an access token, Subsonic keeps a salted token.
class Account {
  const Account({
    required this.id,
    required this.kind,
    required this.baseUrl,
    required this.username,
    required this.serverName,
    this.token,
    this.userId,
    this.salt,
  });

  final String id;
  final ServerKind kind;
  final String baseUrl;
  final String username;
  final String serverName;

  /// Jellyfin: access token. Subsonic: md5(password + salt).
  final String? token;

  /// Jellyfin only.
  final String? userId;

  /// Subsonic only.
  final String? salt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'baseUrl': baseUrl,
        'username': username,
        'serverName': serverName,
        'token': token,
        'userId': userId,
        'salt': salt,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        kind: ServerKind.values.byName(j['kind'] as String),
        baseUrl: j['baseUrl'] as String,
        username: j['username'] as String,
        serverName: j['serverName'] as String,
        token: j['token'] as String?,
        userId: j['userId'] as String?,
        salt: j['salt'] as String?,
      );
}
