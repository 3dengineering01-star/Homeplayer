import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/connection.dart';
import '../services/quality.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A subtitle file the server sends apart from the video: an .srt or .ass next to the file
/// on the server, or text subtitles it takes out of a video it converts.
class ExternalSubtitle {
  const ExternalSubtitle({required this.url, this.title, this.language});

  final Uri url;
  final String? title;

  /// ISO 639 code as the server knows it, e.g. "rus".
  final String? language;
}

/// Something the player can open, independent of which server it came from.
class PlayItem {
  const PlayItem({
    required this.title,
    required this.url,
    required this.isVideo,
    this.subtitle,
    this.artwork,
    this.headers = const {},
    this.audioTrackId,
    this.notice,
    this.reporter,
    this.convertedTo,
    this.withQuality,
    this.subtitles = const [],
    this.favorite,
    this.container,
    this.tvUrl,
    this.ref,
    this.duration,
  });

  final String title;
  final String? subtitle;
  final Uri url;
  final Uri? artwork;
  final bool isVideo;

  /// Sent with both the stream and the artwork request.
  final Map<String, String> headers;

  /// mpv audio track to switch to once the file is open, when the default one can't be decoded.
  final String? audioTrackId;

  /// Shown to the user when playback starts, e.g. why another audio track was picked.
  final String? notice;

  /// Tells the server what is playing; null when the server keeps no history.
  final PlaybackReporter? reporter;

  /// Subtitles to add to the player next to those inside the file.
  final List<ExternalSubtitle> subtitles;

  /// Bitrate the server converts the video to; null for the original file.
  final int? convertedTo;

  /// The same item again in another quality, for switching while it plays; null when the
  /// server cannot convert (music, Subsonic).
  final Future<PlayItem> Function(VideoQuality quality)? withQuality;

  /// The track's mark in the server's favorites; null where it cannot be marked (videos,
  /// downloads played without the server).
  final ItemFavorite? favorite;

  /// The file's container as the server names it ("mkv", "mp4"), for telling a TV its type.
  final String? container;

  /// The link to give a TV instead of [url]: the same file at the server's home address, which
  /// the TV can reach when the phone uses an internet one. Null when [url] will do.
  final Future<Uri> Function()? tvUrl;

  /// Where the track comes from, to find it again after a restart and to ask its server for
  /// lyrics or similar songs; null for videos and what cannot be found again.
  final TrackRef? ref;

  /// The length the server gives for the file. mpv's own guess is wrong for a stream the server
  /// converts (it estimates from the bitrate).
  final Duration? duration;

  PlayItem copyWith({
    Uri? url,
    String? audioTrackId,
    String? notice,
    PlaybackReporter? reporter,
    int? convertedTo,
    Future<PlayItem> Function(VideoQuality quality)? withQuality,
    List<ExternalSubtitle>? subtitles,
  }) =>
      PlayItem(
        title: title,
        subtitle: subtitle,
        url: url ?? this.url,
        artwork: artwork,
        isVideo: isVideo,
        headers: headers,
        audioTrackId: audioTrackId ?? this.audioTrackId,
        notice: notice ?? this.notice,
        reporter: reporter ?? this.reporter,
        convertedTo: convertedTo ?? this.convertedTo,
        withQuality: withQuality ?? this.withQuality,
        subtitles: subtitles ?? this.subtitles,
        favorite: favorite,
        container: container,
        tvUrl: tvUrl,
        ref: ref,
        duration: duration,
      );
}

enum TrackSource { jellyfin, subsonic, download }

/// A track as its server knows it: the server's account and the track's id there. A download
/// keeps the Jellyfin id and account of the track it was made from.
class TrackRef {
  const TrackRef(this.source, this.id, {this.accountId});

  final TrackSource source;
  final String id;
  final String? accountId;

  Map<String, dynamic> toJson() => {'source': source.name, 'id': id, 'accountId': ?accountId};

  /// Null for anything this version cannot read (a newer app's entry, a damaged file).
  static TrackRef? fromJson(Object? j) {
    if (j is! Map) return null;
    final source = TrackSource.values.where((s) => s.name == j['source']).firstOrNull;
    final id = j['id'];
    final account = j['accountId'];
    if (source == null || id is! String || (account != null && account is! String)) return null;
    return TrackRef(source, id, accountId: account as String?);
  }

  @override
  bool operator ==(Object other) =>
      other is TrackRef && other.source == source && other.id == id && other.accountId == accountId;

  @override
  int get hashCode => Object.hash(source, id, accountId);
}

/// A track's heart: marked as a favorite on its server. [marked] changes at once when tapped and
/// goes back if the server refuses.
abstract class ItemFavorite {
  ValueNotifier<bool> get marked;

  Future<void> set(bool on);

  Future<void> toggle() => set(!marked.value);
}

/// [ItemFavorite] over one call that tells the server; the heart shows the new state at once.
class ServerFavorite extends ItemFavorite {
  ServerFavorite(bool marked, this._send) : marked = ValueNotifier(marked);

  @override
  final ValueNotifier<bool> marked;

  final Future<void> Function(bool on) _send;

  @override
  Future<void> set(bool on) async {
    final before = marked.value;
    marked.value = on;
    try {
      await _send(on);
    } catch (e) {
      marked.value = before;
      rethrow;
    }
  }
}

/// Playback events for the server: Jellyfin keeps the resume point and the played mark from
/// them, Subsonic counts plays. Implementations swallow network errors.
abstract class PlaybackReporter {
  Future<void> started(Duration position);
  Future<void> progress(Duration position, {required bool paused});
  /// [duration] of the file, when the player knows it.
  Future<void> stopped(Duration position, {Duration? duration});
}

/// Watched by the rule Jellyfin applies to stop reports: past 90% (its default MaxResumePct).
bool isWatched(Duration position, Duration? duration) =>
    duration != null && duration > Duration.zero && position >= duration * 0.9;

/// Local file for downloads, otherwise fetched from the server with [PlayItem.headers].
extension PlayItemArtwork on PlayItem {
  String? get artworkPath => artwork?.scheme == 'file' ? artwork!.toFilePath() : null;
}

/// Audio codecs the bundled libmpv decodes, as Jellyfin names them. The media_kit build has
/// no TrueHD/MLP decoder (checked with mpv's decoder-list on a Pixel 10a).
const supportedAudioCodecs = [
  'aac', 'mp3', 'mp2', 'ac3', 'eac3', 'dts', 'flac', 'opus', 'vorbis', 'alac',
  'pcm_s16le', 'pcm_s24le', 'pcm_s32le', 'pcm_f32le',
];

bool canDecodeAudio(String? codec) {
  if (codec == null) return true;
  final c = codec.toLowerCase();
  return supportedAudioCodecs.contains(c) || c.startsWith('pcm');
}

String codecLabel(String? codec) => switch (codec?.toLowerCase()) {
      'truehd' => 'TrueHD',
      'mlp' => 'MLP',
      'dts' => 'DTS',
      'ac3' => 'AC3',
      'eac3' => 'E-AC3',
      'aac' => 'AAC',
      'flac' => 'FLAC',
      'opus' => 'Opus',
      null => 'this audio format',
      final c => c.toUpperCase(),
    };

/// Accepts "192.168.1.10:8096", "http://host/jellyfin/" and the like.
String normalizeBaseUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) throw ApiException('Enter the server address');
  if (!s.contains('://')) s = 'http://$s';
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    throw ApiException('Invalid server address');
  }
  return s;
}

/// What went wrong with a request, when it is the connection rather than the server's answer.
enum NetProblem {
  /// The phone has no network at all (airplane mode, no Wi-Fi and no mobile data).
  offline,

  /// There is a network, but the server cannot be reached on it.
  unreachable,

  /// The server took too long to answer.
  timeout,
}

/// The connection problem behind [e], or null when [e] is something else (a refusal, a bad
/// answer). [offline] is what the phone itself says about its network.
NetProblem? netProblem(Object e, {bool offline = false}) {
  final s = e.toString();
  final timedOut = e is TimeoutException || s.contains('TimeoutException');
  final noConnection = s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('HandshakeException') ||
      s.contains('Connection closed');
  if (!timedOut && !noConnection) return null;
  // ENETUNREACH: Android answers so at once in airplane mode, before the app hears of it.
  if (offline || s.contains('Network is unreachable') || s.contains('errno = 101')) return NetProblem.offline;
  return timedOut ? NetProblem.timeout : NetProblem.unreachable;
}

/// The message for [e] shown to people. Pure: [offline] comes from the caller.
String errorMessage(Object e, {bool offline = false}) => switch (netProblem(e, offline: offline)) {
      NetProblem.offline => 'No connection. Downloaded movies and music still play: open Downloads.',
      NetProblem.unreachable =>
        'Cannot reach the server. Check the address, and that the phone is on the same network or Tailscale.',
      NetProblem.timeout => 'The server did not answer in time. Check the connection and try again.',
      // Anything else as it is, without tokens or links that carry them.
      null => redactSecrets(e.toString()),
    };

/// [errorMessage], with what the phone currently says about its network.
String describeError(Object e) => errorMessage(e, offline: Connection.offline.value);

/// Query parameters that carry a sign-in: Jellyfin's api_key, Subsonic's t (token), s (salt)
/// and p (password), and the usual names elsewhere.
const _secretParams = {
  'api_key', 'apikey', 'token', 'access_token', 'accesstoken', 'x-emby-token', 'x-mediabrowser-token',
  't', 's', 'p', 'pw', 'password', 'auth', 'key', 'signature', 'sig',
};

final _urlPattern = RegExp(r'''[a-zA-Z][a-zA-Z0-9+.\-]*://[^\s"'<>()\[\]]+''');

// Token="…", "AccessToken":"…", api_key=…, password: … outside links.
final _fieldPattern = RegExp(
    r'''("?)\b(api_key|apikey|accesstoken|access_token|x-emby-token|x-mediabrowser-token|token|password|pw)\1(\s*[=:]\s*)("?)[^"\s,&;]+''',
    caseSensitive: false);
final _bearerPattern = RegExp(r'Bearer\s+\S+', caseSensitive: false);

// Jellyfin tokens and Subsonic's md5 token are 32 hex characters. Item ids look the same and
// are hidden too, which costs little in a problem report.
final _hexPattern = RegExp(r'\b[0-9a-fA-F]{32,}\b');

/// [text] without sign-in secrets, for logs and problem reports: a link that carries a token
/// or a password is removed whole, other links lose their query, and token fields are hidden.
String redactSecrets(String text) {
  var s = text.replaceAllMapped(_urlPattern, (m) {
    final uri = Uri.tryParse(m[0]!);
    if (uri == null || uri.userInfo.isNotEmpty) return '[link removed]';
    if (uri.queryParametersAll.keys.any((k) => _secretParams.contains(k.toLowerCase()))) return '[link removed]';
    return uri.hasQuery || uri.hasFragment ? '${uri.scheme}://${uri.authority}${uri.path}' : m[0]!;
  });
  s = s.replaceAllMapped(_fieldPattern, (m) => '${m[1]}${m[2]}${m[1]}${m[3]}${m[4]}[hidden]');
  s = s.replaceAll(_bearerPattern, 'Bearer [hidden]');
  return s.replaceAll(_hexPattern, '[hidden]');
}

/// 1:05:09 or 4:07.
String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
