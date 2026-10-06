import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../services/account_store.dart';
import 'common.dart';

const _timeout = Duration(seconds: 15);

class SubsonicEntry {
  const SubsonicEntry({required this.id, required this.title, this.subtitle, this.coverArt, this.duration});
  final String id;
  final String title;
  final String? subtitle;
  final String? coverArt;
  final Duration? duration;
}

/// Subsonic API with token auth (Navidrome, Gonic, Airsonic and others).
class SubsonicClient {
  SubsonicClient(this.account, {http.Client? client}) : _http = client ?? http.Client();
  final Account account;
  final http.Client _http;

  static Future<Account> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final salt = randomHex(8);
    final token = md5.convert(utf8.encode(password + salt)).toString();
    final account = Account(
      id: 'ss:$baseUrl:$username',
      kind: ServerKind.subsonic,
      baseUrl: baseUrl,
      username: username,
      serverName: Uri.parse(baseUrl).host,
      token: token,
      salt: salt,
    );
    final r = await SubsonicClient(account)._call('ping');
    final type = r['type'] as String?;
    if (type == null) return account;
    return Account(
      id: account.id,
      kind: account.kind,
      baseUrl: baseUrl,
      username: username,
      serverName: '${type[0].toUpperCase()}${type.substring(1)} · ${Uri.parse(baseUrl).host}',
      token: token,
      salt: salt,
    );
  }

  Uri _uri(String method, [Map<String, String>? query]) =>
      Uri.parse('${account.baseUrl}/rest/$method').replace(queryParameters: {
        'u': account.username,
        't': account.token!,
        's': account.salt!,
        'v': '1.16.1',
        'c': 'homeplay',
        'f': 'json',
        ...?query,
      });

  Future<Map<String, dynamic>> _call(String method, [Map<String, String>? query]) async {
    final res = await _http.get(_uri(method, query)).timeout(_timeout);
    if (res.statusCode != 200) throw ApiException('Server answered ${res.statusCode}. Is this a Subsonic server?');
    final Map<String, dynamic> r;
    try {
      r = (jsonDecode(res.body) as Map<String, dynamic>)['subsonic-response'] as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Not a Subsonic server');
    }
    if (r['status'] != 'ok') {
      final err = r['error'] as Map?;
      throw ApiException(err?['code'] == 40 ? 'Wrong username or password' : '${err?['message'] ?? 'Request failed'}');
    }
    return r;
  }

  Future<List<SubsonicEntry>> artists() async {
    final r = await _call('getArtists');
    final index = ((r['artists'] as Map?)?['index'] as List?) ?? const [];
    return [
      for (final group in index)
        for (final a in ((group as Map)['artist'] as List?) ?? const [])
          SubsonicEntry(
            id: '${a['id']}',
            title: '${a['name']}',
            subtitle: a['albumCount'] != null ? '${a['albumCount']} albums' : null,
            coverArt: a['coverArt'] as String?,
          ),
    ];
  }

  Future<List<SubsonicEntry>> albums(String artistId) async {
    final r = await _call('getArtist', {'id': artistId});
    final list = ((r['artist'] as Map?)?['album'] as List?) ?? const [];
    return [
      for (final a in list)
        SubsonicEntry(
          id: '${a['id']}',
          title: '${a['name'] ?? a['title']}',
          subtitle: a['year']?.toString(),
          coverArt: a['coverArt'] as String?,
        ),
    ];
  }

  Future<List<SubsonicEntry>> songs(String albumId) async {
    final r = await _call('getAlbum', {'id': albumId});
    final list = ((r['album'] as Map?)?['song'] as List?) ?? const [];
    return [
      for (final s in list)
        SubsonicEntry(
          id: '${s['id']}',
          title: '${s['title']}'.trim(),
          subtitle: (s['artist'] as String?)?.trim(),
          coverArt: s['coverArt'] as String?,
          duration: s['duration'] is num ? Duration(seconds: (s['duration'] as num).toInt()) : null,
        ),
    ];
  }

  /// Songs matching [query] (title, artist, album), for voice search in the car.
  Future<List<SubsonicEntry>> searchSongs(String query) async {
    final r = await _call('search3', {'query': query, 'songCount': '50', 'albumCount': '0', 'artistCount': '0'});
    final list = ((r['searchResult3'] as Map?)?['song'] as List?) ?? const [];
    return [
      for (final s in list)
        SubsonicEntry(
          id: '${s['id']}',
          title: '${s['title']}'.trim(),
          subtitle: (s['artist'] as String?)?.trim(),
          coverArt: s['coverArt'] as String?,
          duration: s['duration'] is num ? Duration(seconds: (s['duration'] as num).toInt()) : null,
        ),
    ];
  }

  Uri? coverUrl(String? coverArt, {int size = 300}) =>
      coverArt == null ? null : _uri('getCoverArt', {'id': coverArt, 'size': '$size'});

  PlayItem toPlayItem(SubsonicEntry song) => PlayItem(
        title: song.title,
        subtitle: song.subtitle,
        url: _uri('stream', {'id': song.id}),
        artwork: coverUrl(song.coverArt, size: 600),
        isVideo: false,
        reporter: _Scrobbler(this, song),
      );

  Future<void> _scrobble(String id, {required bool submission}) async {
    try {
      await _call('scrobble', {'id': id, 'submission': '$submission'});
    } catch (e) {
      debugPrint('homeplay scrobble failed: $e');
    }
  }
}

/// "Now playing" when a track starts; a counted play once half of it (or 4 minutes) was heard,
/// the usual scrobbling rule.
class _Scrobbler implements PlaybackReporter {
  _Scrobbler(this._client, this._song);
  final SubsonicClient _client;
  final SubsonicEntry _song;

  @override
  Future<void> started(Duration position) => _client._scrobble(_song.id, submission: false);

  @override
  Future<void> progress(Duration position, {required bool paused}) async {}

  @override
  Future<void> stopped(Duration position, {Duration? duration}) async {
    final total = _song.duration;
    final needed = total == null ? const Duration(seconds: 30) : (total ~/ 2 < const Duration(minutes: 4) ? total ~/ 2 : const Duration(minutes: 4));
    if (position >= needed) await _client._scrobble(_song.id, submission: true);
  }
}
