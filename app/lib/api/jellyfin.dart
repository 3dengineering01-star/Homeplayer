import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/account.dart';
import 'common.dart';

const _appVersion = '0.1.0';
const _timeout = Duration(seconds: 15);

class JellyfinItem {
  JellyfinItem(this._j);
  final Map<String, dynamic> _j;

  String get id => _j['Id'] as String;
  String get name => (_j['Name'] as String?) ?? '';
  String get type => (_j['Type'] as String?) ?? '';
  bool get isFolder => (_j['IsFolder'] as bool?) ?? false;
  String? get collectionType => _j['CollectionType'] as String?;
  bool get isVirtual => _j['LocationType'] == 'Virtual';
  bool get isVideo => _j['MediaType'] == 'Video';
  bool get isPlayable => !isFolder && (_j['MediaType'] == 'Video' || _j['MediaType'] == 'Audio');
  bool get hasPrimaryImage => (_j['ImageTags'] as Map?)?.containsKey('Primary') ?? false;
  double get imageAspect => ((_j['PrimaryImageAspectRatio'] as num?)?.toDouble() ?? 1).clamp(0.6, 1.8);

  /// Files of the same movie or episode (4K and 1080p, a director's cut...); Jellyfin only
  /// sends the count when it is not 1.
  int get versionCount => (_j['MediaSourceCount'] as num?)?.toInt() ?? 1;

  Map<String, dynamic> get _user => (_j['UserData'] as Map<String, dynamic>?) ?? const {};
  bool get played => (_user['Played'] as bool?) ?? false;

  /// Where playback stopped last time; zero when there is nothing to resume.
  Duration get resumePosition => Duration(microseconds: ((_user['PlaybackPositionTicks'] as num?) ?? 0).toInt() ~/ 10);

  /// 0..1 for something started but not finished, otherwise null.
  double? get progress {
    final p = _user['PlayedPercentage'] as num?;
    return p == null || p <= 0 ? null : (p / 100).clamp(0.0, 1.0);
  }

  String? get subtitle {
    switch (type) {
      case 'Episode':
        final s = _j['ParentIndexNumber'], e = _j['IndexNumber'];
        final code = (s != null && e != null) ? 'S${s}E$e' : null;
        return [_j['SeriesName'], code].whereType<String>().join(' · ');
      case 'Audio':
        final artists = (_j['Artists'] as List?)?.cast<String>() ?? const [];
        return artists.isNotEmpty ? artists.join(', ') : _j['AlbumArtist'] as String?;
      case 'MusicAlbum':
        return _j['AlbumArtist'] as String?;
      default:
        return _j['ProductionYear']?.toString();
    }
  }
}

/// One file of an item that has several, as Jellyfin's PlaybackInfo lists them.
class MediaVersion {
  MediaVersion(this._j);
  final Map<String, dynamic> _j;

  String get id => _j['Id'] as String;

  /// Jellyfin takes it from the file name, e.g. "2160p" for "Movie - 2160p.mkv".
  String get name => (_j['Name'] as String?) ?? '';

  /// "4K · HEVC · Dolby Vision · 58.2 GB", without what [name] already says.
  String get details {
    final video = ((_j['MediaStreams'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((s) => s['Type'] == 'Video')
        .firstOrNull;
    final parts = [
      if (video != null) ...[
        _resolution((video['Width'] as num?)?.toInt(), (video['Height'] as num?)?.toInt()),
        _videoCodec(video['Codec'] as String?),
        _range(video['VideoRangeType'] as String?),
      ],
      _size((_j['Size'] as num?)?.toInt()),
    ].whereType<String>().where((p) => !name.toLowerCase().contains(p.toLowerCase()));
    return parts.join(' · ');
  }

  // By width: a 1920x800 scope movie is still 1080p.
  static String? _resolution(int? width, int? height) => switch (width) {
        null => null,
        >= 3200 => '4K',
        >= 1800 => '1080p',
        >= 1200 => '720p',
        _ => height == null ? null : '${height}p',
      };

  static String? _videoCodec(String? codec) => switch (codec?.toLowerCase()) {
        null => null,
        'h264' => 'H.264',
        'hevc' => 'HEVC',
        'mpeg4' => 'MPEG-4',
        'mpeg2video' => 'MPEG-2',
        final c => c.toUpperCase(),
      };

  static String? _range(String? type) => switch (type) {
        null || 'SDR' || 'Unknown' => null,
        final t when t.startsWith('DOVI') => 'Dolby Vision',
        'HDR10Plus' => 'HDR10+',
        final t => t,
      };

  // In 1024-based units, as Windows shows file sizes.
  static String? _size(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    const gb = 1024 * 1024 * 1024;
    return bytes >= gb ? '${(bytes / gb).toStringAsFixed(1)} GB' : '${(bytes / (1024 * 1024)).round()} MB';
  }
}

class JellyfinClient {
  JellyfinClient(this.account, this.deviceId);

  final Account account;
  final String deviceId;

  String get _base => account.baseUrl;

  static String _authHeader(String deviceId, [String? token]) =>
      'MediaBrowser Client="Homeplay", Device="Android", DeviceId="$deviceId", Version="$_appVersion"'
      '${token != null ? ', Token="$token"' : ''}';

  Map<String, String> get headers => {'Authorization': _authHeader(deviceId, account.token)};

  static Future<Account> login({
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/Users/AuthenticateByName'),
          headers: {'Authorization': _authHeader(deviceId), 'Content-Type': 'application/json'},
          body: jsonEncode({'Username': username, 'Pw': password}),
        )
        .timeout(_timeout);
    if (res.statusCode == 401) throw ApiException('Wrong username or password');
    if (res.statusCode != 200) throw ApiException('Server answered ${res.statusCode}. Is this a Jellyfin server?');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final userId = (j['User'] as Map)['Id'] as String;
    final serverName = await _serverName(baseUrl) ?? Uri.parse(baseUrl).host;
    return Account(
      id: 'jf:$baseUrl:$userId',
      kind: ServerKind.jellyfin,
      baseUrl: baseUrl,
      username: username,
      serverName: serverName,
      token: j['AccessToken'] as String,
      userId: userId,
    );
  }

  static Future<String?> _serverName(String baseUrl) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/System/Info/Public')).timeout(_timeout);
      return (jsonDecode(res.body) as Map)['ServerName'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final res = await http.get(uri, headers: headers).timeout(_timeout);
    if (res.statusCode == 401) throw ApiException('Session expired. Remove the server and sign in again.');
    if (res.statusCode != 200) throw ApiException('Server answered ${res.statusCode} for $path');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  List<JellyfinItem> _items(Map<String, dynamic> j) =>
      ((j['Items'] as List?) ?? const []).map((e) => JellyfinItem(e as Map<String, dynamic>)).toList();

  /// Libraries, without Live TV: Jellyfin lists it even with no tuner, and this app has no TV guide.
  Future<List<JellyfinItem>> views() async => _items(await _get('/UserViews', {'userId': account.userId!}))
      .where((v) => v.collectionType != 'livetv')
      .toList();

  Future<List<JellyfinItem>> children(String parentId) async => _items(await _get('/Items', {
        'userId': account.userId!,
        'parentId': parentId,
        'sortBy': 'ParentIndexNumber,IndexNumber,SortName',
        'sortOrder': 'Ascending',
        'fields': 'PrimaryImageAspectRatio,MediaSourceCount',
        'enableImageTypes': 'Primary',
        'enableUserData': 'true',
        // Episodes and seasons Jellyfin knows from online metadata but has no files for.
        // Jellyfin 12 does not always honour these filters, so they are dropped below too.
        'excludeLocationTypes': 'Virtual',
        'isMissing': 'false',
      }))
          .where((i) => !i.isVirtual)
          .toList();

  Uri? imageUrl(JellyfinItem item, {int height = 300}) => item.hasPrimaryImage
      ? Uri.parse('$_base/Items/${item.id}/Images/Primary')
          .replace(queryParameters: {'fillHeight': '$height', 'quality': '90'})
      : null;

  /// Direct play: the file goes to mpv untouched. Transcoding comes later,
  /// for slow mobile connections. [versionId] picks one of several files; null is the default.
  Uri streamUrl(JellyfinItem item, {String? versionId}) =>
      Uri.parse('$_base/${item.isVideo ? 'Videos' : 'Audio'}/${item.id}/stream').replace(queryParameters: {
        'static': 'true',
        'ApiKey': account.token!,
        'mediaSourceId': ?versionId,
      });

  /// The files of an item with [JellyfinItem.versionCount] above 1, in the server's order.
  Future<List<MediaVersion>> versions(JellyfinItem item) async =>
      ((await _playbackInfo(item.id, const {}))['MediaSources'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(MediaVersion.new)
          .toList();

  /// What this phone can play, so the server knows when it has to convert something.
  static final Map<String, dynamic> _deviceProfile = {
    'Name': 'Homeplay',
    'MaxStreamingBitrate': 200000000,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container': 'mkv,mp4,m4v,mov,webm,avi,ts,m2ts,mpegts',
        'VideoCodec': 'h264,hevc,av1,vp9,vp8,mpeg4,mpeg2video',
        'AudioCodec': supportedAudioCodecs.join(','),
      },
    ],
    // Video is copied as is; only the audio gets converted.
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'mp4',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'VideoCodec': 'hevc,h264,av1,vp9',
        'AudioCodec': 'aac,eac3,ac3',
        'MaxAudioChannels': '6',
        'MinSegments': 1,
        'BreakOnNonKeyFrames': true,
      },
    ],
    // Every subtitle format is fine inside the file: without this the server may burn them in.
    'SubtitleProfiles': [
      for (final f in ['ass', 'ssa', 'srt', 'subrip', 'vtt', 'webvtt', 'pgssub', 'dvdsub', 'dvbsub', 'mov_text'])
        {'Format': f, 'Method': 'Embed'},
    ],
  };

  /// Direct play when the phone can decode the audio; otherwise another audio track in the
  /// file, and only as a last resort audio converted by the server. [versionId] picks one of
  /// several files of the item; null is the server's default.
  Future<PlayItem> resolve(JellyfinItem item, {String? versionId}) async {
    final direct = toPlayItem(item, versionId: versionId);
    if (!item.isVideo) return direct;

    final version = {'MediaSourceId': ?versionId};
    final info = await _playbackInfo(item.id, version);
    final sources = ((info['MediaSources'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final source = sources.where((s) => s['Id'] == versionId).firstOrNull ?? sources.firstOrNull;
    if (source == null) return direct;
    final played = direct.copyWith(
      reporter: _reporter(item, source['Id'] as String?, info['PlaySessionId'] as String?, 'DirectPlay'),
    );

    final audio = ((source['MediaStreams'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((s) => s['Type'] == 'Audio')
        .toList();
    if (audio.isEmpty) return played;
    final current = audio.firstWhere((s) => s['Index'] == source['DefaultAudioStreamIndex'], orElse: () => audio.first);
    if (canDecodeAudio(current['Codec'] as String?)) return played;
    final wanted = codecLabel(current['Codec'] as String?);

    final playable = audio.where((s) => canDecodeAudio(s['Codec'] as String?)).toList()
      ..sort((a, b) => ((b['Channels'] as int?) ?? 0).compareTo((a['Channels'] as int?) ?? 0));
    if (playable.isNotEmpty) {
      final alt = playable.first;
      // mpv numbers audio tracks from 1 in file order, the same order Jellyfin lists them in.
      return played.copyWith(
        audioTrackId: '${audio.indexOf(alt) + 1}',
        notice: '$wanted isn\'t supported on this phone, playing the ${codecLabel(alt['Codec'] as String?)} track instead',
      );
    }

    // Jellyfin 12 still offers direct play here despite the profile, so ask again with direct
    // play off; video copy stays allowed, so only the audio gets converted.
    final converted = await _playbackInfo(item.id, {
      ...version,
      'AudioStreamIndex': current['Index'],
      'EnableDirectPlay': false,
      'EnableDirectStream': false,
    });
    final convertedSource = ((converted['MediaSources'] as List?) ?? const []).cast<Map<String, dynamic>>().firstOrNull;
    final url = convertedSource?['TranscodingUrl'] as String?;
    // The URL carries the access token, so it never goes to the log.
    debugPrint('homeplay conversion for ${item.name}: ${url == null ? 'refused' : 'ok'}');
    if (url == null) return played.copyWith(notice: '$wanted isn\'t supported on this phone, and the server can\'t convert it');
    return direct.copyWith(
      url: Uri.parse('$_base$url'),
      notice: '$wanted isn\'t supported on this phone, so the server converts the sound. Subtitles are off in this mode.',
      // Its stop report also ends the conversion on the server.
      reporter: _reporter(item, convertedSource?['Id'] as String?, converted['PlaySessionId'] as String?, 'Transcode'),
    );
  }

  Future<Map<String, dynamic>> _playbackInfo(String itemId, Map<String, dynamic> overrides) async {
    final res = await http
        .post(
          Uri.parse('$_base/Items/$itemId/PlaybackInfo').replace(queryParameters: {'userId': account.userId!}),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'DeviceProfile': _deviceProfile,
            'SubtitleStreamIndex': -1,
            'EnableDirectPlay': true,
            'EnableDirectStream': true,
            'EnableTranscoding': true,
            'AllowVideoStreamCopy': true,
            'AllowAudioStreamCopy': true,
            'AutoOpenLiveStream': false,
            ...overrides,
          }),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) throw ApiException('Server answered ${res.statusCode} for PlaybackInfo');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  PlaybackReporter _reporter(JellyfinItem item, String? mediaSourceId, String? playSessionId, String playMethod) =>
      _JellyfinReporter(this, item.id, mediaSourceId ?? item.id, playSessionId, playMethod);

  Future<void> _report(String path, Map<String, dynamic> body) async {
    try {
      await http
          .post(Uri.parse('$_base$path'),
              headers: {...headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_timeout);
    } catch (e) {
      debugPrint('homeplay report $path failed: $e');
    }
  }

  PlayItem toPlayItem(JellyfinItem item, {String? versionId}) => PlayItem(
        title: item.name,
        subtitle: item.subtitle,
        url: streamUrl(item, versionId: versionId),
        artwork: imageUrl(item, height: 600),
        isVideo: item.isVideo,
        headers: headers,
        reporter: _reporter(item, versionId, null, 'DirectPlay'),
      );
}

/// Jellyfin keeps the resume point and the played mark from these reports.
class _JellyfinReporter implements PlaybackReporter {
  _JellyfinReporter(this._client, this._itemId, this._mediaSourceId, this._playSessionId, this._playMethod);

  final JellyfinClient _client;
  final String _itemId;
  final String _mediaSourceId;
  final String? _playSessionId;
  final String _playMethod;

  Map<String, dynamic> _body(Duration position, {bool paused = false}) => {
        'ItemId': _itemId,
        'MediaSourceId': _mediaSourceId,
        'PlaySessionId': _playSessionId,
        'PlayMethod': _playMethod,
        'PositionTicks': position.inMicroseconds * 10,
        'IsPaused': paused,
        'CanSeek': true,
      };

  @override
  Future<void> started(Duration position) => _client._report('/Sessions/Playing', _body(position));

  @override
  Future<void> progress(Duration position, {required bool paused}) =>
      _client._report('/Sessions/Playing/Progress', _body(position, paused: paused));

  @override
  Future<void> stopped(Duration position) => _client._report('/Sessions/Playing/Stopped', _body(position));
}
