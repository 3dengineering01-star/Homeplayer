class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
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
    this.onClose,
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

  /// Called when the player closes, e.g. to let the server stop a conversion.
  final Future<void> Function()? onClose;

  PlayItem copyWith({Uri? url, String? audioTrackId, String? notice, Future<void> Function()? onClose}) => PlayItem(
        title: title,
        subtitle: subtitle,
        url: url ?? this.url,
        artwork: artwork,
        isVideo: isVideo,
        headers: headers,
        audioTrackId: audioTrackId ?? this.audioTrackId,
        notice: notice ?? this.notice,
        onClose: onClose ?? this.onClose,
      );
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
