import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'lyrics.dart';

/// Lyrics from LRCLIB (lrclib.net), a free open collection of timed lyrics, for songs the
/// music server has none for. Only the song's title, artist and length go there.
class LrcLib {
  LrcLib({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  static const _key = 'lyrics_lrclib';

  /// Whether to ask LRCLIB at all (Settings → Music); on unless turned off.
  static Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_key) ?? true;

  static Future<void> setEnabled(bool on) async => (await SharedPreferences.getInstance()).setBool(_key, on);

  /// The lyrics of [title] by [artist]; null when LRCLIB has none. [duration] picks the right
  /// recording among several (a live version runs longer).
  Future<Lyrics?> find({required String title, String? artist, Duration? duration}) async {
    // Several performers come as "A, B": the first one alone finds more.
    final names = <String?>[
      artist,
      if (artist != null && artist.contains(',')) artist.split(',').first.trim(),
    ];
    for (final name in names) {
      final res = await _http.get(
        Uri.https('lrclib.net', '/api/search', {'track_name': title, if (name != null && name.isNotEmpty) 'artist_name': name}),
        // LRCLIB asks apps to name themselves.
        headers: const {'User-Agent': 'OwnMedia (https://ownmedia.app)'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint('homeplay lrclib answered ${res.statusCode}');
        return null;
      }
      final found = lyricsFromLrcLib(pickLrcLib(jsonDecode(res.body), duration));
      if (found != null) return found;
    }
    return null;
  }
}

/// The best of LRCLIB's search results: the ones within 3 seconds of [duration] when there are
/// (the same recording), else all of them; timed lyrics before plain ones, then the closest
/// length. The same song in another edition has the same words, so a length that does not match
/// still gets lyrics.
Map<String, dynamic>? pickLrcLib(Object? results, Duration? duration) {
  if (results is! List) return null;
  final all = <Map<String, dynamic>>[
    for (final r in results)
      if (r is Map<String, dynamic> &&
          (r['syncedLyrics'] is String || r['plainLyrics'] is String || r['instrumental'] == true))
        r,
  ];
  final same = [
    for (final r in all)
      if (duration != null && r['duration'] is num && ((r['duration'] as num) - duration.inMilliseconds / 1000).abs() <= 3) r,
  ];
  final fits = same.isNotEmpty ? same : all;
  if (fits.isEmpty) return null;
  double off(Map<String, dynamic> r) =>
      duration == null || r['duration'] is! num ? 0 : ((r['duration'] as num) - duration.inMilliseconds / 1000).abs();
  int timed(Map<String, dynamic> r) => r['syncedLyrics'] is String && (r['syncedLyrics'] as String).trim().isNotEmpty ? 0 : 1;
  fits.sort((a, b) {
    final t = timed(a).compareTo(timed(b));
    return t != 0 ? t : off(a).compareTo(off(b));
  });
  return fits.first;
}

/// One LRCLIB result as lyrics: the timed ones (LRC) when there are, else the plain text. An
/// instrumental says so.
Lyrics? lyricsFromLrcLib(Map<String, dynamic>? r) {
  if (r == null) return null;
  if (r['instrumental'] == true) return const Lyrics([LyricLine('♪ Instrumental ♪')], source: 'LRCLIB');
  final found = lyricsFromText(r['syncedLyrics'] as String?) ?? lyricsFromText(r['plainLyrics'] as String?);
  return found == null ? null : Lyrics(found.lines, source: 'LRCLIB');
}
