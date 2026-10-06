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
      );
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

String describeError(Object e) {
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('ClientException')) {
    return 'Cannot reach the server. Check the address, and that the phone is on the same network or Tailscale.';
  }
  if (s.contains('TimeoutException')) return 'The server did not answer in time.';
  return s;
}

/// 1:05:09 or 4:07.
String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
