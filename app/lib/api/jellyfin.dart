import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../services/quality.dart';
import '../services/search_filters.dart';
import 'common.dart';

const _appVersion = '0.1.0';
const _timeout = Duration(seconds: 15);

class JellyfinItem {
  JellyfinItem(this._j);
  final Map<String, dynamic> _j;

  String get id => _j['Id'] as String;
  String get name => (_j['Name'] as String?)?.trim() ?? '';
  String get type => (_j['Type'] as String?) ?? '';
  bool get isFolder => (_j['IsFolder'] as bool?) ?? false;
  String? get collectionType => _j['CollectionType'] as String?;
  bool get isVirtual => _j['LocationType'] == 'Virtual';
  bool get isVideo => _j['MediaType'] == 'Video';
  bool get isPhoto => !isFolder && _j['MediaType'] == 'Photo';
  bool get isPlayable => !isFolder && (_j['MediaType'] == 'Video' || _j['MediaType'] == 'Audio');
  bool get hasPrimaryImage => (_j['ImageTags'] as Map?)?.containsKey('Primary') ?? false;

  /// The album whose cover a track shows, when the album has one.
  String? get albumImageOwner => _j['AlbumPrimaryImageTag'] == null ? null : _j['AlbumId'] as String?;
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

  // --- For the home screen and the details page ---

  String? get overview => (_j['Overview'] as String?)?.trim();
  int? get year => (_j['ProductionYear'] as num?)?.toInt();
  String? get seriesId => _j['SeriesId'] as String?;
  String? get seriesName => (_j['SeriesName'] as String?)?.trim();
  String? get album => _text(_j['Album']);
  String? get albumId => _j['AlbumId'] as String?;
  String? get albumArtist => _text(_j['AlbumArtist']);

  /// A track's performers; tags sometimes come padded with spaces.
  List<String> get artists => [
        for (final a in (_j['Artists'] as List?) ?? const []) ?_text(a),
      ];

  /// The file's format as the server names it ("mp3", "flac").
  String? get container => (_j['Container'] as String?)?.split(',').first.trim();

  /// Where the file lies on the server, when asked for.
  String? get path => _j['Path'] as String?;

  /// The file's own name, as on the server's disk ("01-Cluster One.mp3").
  String? get fileName => path?.split(RegExp(r'[/\\]')).last;

  /// A track's number on its album: the tag, else the number the file name starts with
  /// ("01-Cluster One.mp3"), which the server does not always take.
  int? get trackNumber => indexNumber ?? trackNumberFromPath(_j['Path'] as String?);

  /// When the server first saw the file.
  DateTime? get dateCreated => DateTime.tryParse((_j['DateCreated'] as String?) ?? '');

  /// The entry's own id in a playlist, which removing it from the playlist needs.
  String? get playlistEntryId => _j['PlaylistItemId'] as String?;

  /// How many items a folder or playlist holds, when the server says.
  int? get childCount => (_j['ChildCount'] as num?)?.toInt();

  static String? _text(Object? v) {
    final t = (v as String?)?.trim();
    return t == null || t.isEmpty ? null : t;
  }
  String? get seasonId => _j['SeasonId'] as String?;
  int? get indexNumber => (_j['IndexNumber'] as num?)?.toInt();
  int? get seasonNumber => (_j['ParentIndexNumber'] as num?)?.toInt();

  /// Length of a movie or episode.
  Duration? get runTime {
    final ticks = _j['RunTimeTicks'] as num?;
    return ticks == null || ticks <= 0 ? null : Duration(microseconds: ticks.toInt() ~/ 10);
  }

  /// Audience rating out of 10 (from TMDb and the like).
  double? get rating => (_j['CommunityRating'] as num?)?.toDouble();

  /// Age rating: "PG-13", "16+"...
  String? get ageRating => (_j['OfficialRating'] as String?)?.trim();

  List<String> get genres => [for (final g in (_j['Genres'] as List?) ?? const []) '$g'];

  /// Episodes of a series or season not watched yet.
  int? get unwatched => (_user['UnplayedItemCount'] as num?)?.toInt();

  /// The item whose wide picture to show: its own, or for an episode or season its series'.
  String? get backdropOwner => ((_j['BackdropImageTags'] as List?)?.isNotEmpty ?? false)
      ? id
      : _j['ParentBackdropItemId'] as String?;

  /// A wide picture of the item itself (an episode's still), as Jellyfin calls it Thumb or Primary.
  bool get hasThumb => (_j['ImageTags'] as Map?)?.containsKey('Thumb') ?? false;

  String? get subtitle {
    switch (type) {
      case 'Episode':
        final s = _j['ParentIndexNumber'], e = _j['IndexNumber'];
        final code = (s != null && e != null) ? 'S${s}E$e' : null;
        return [_j['SeriesName'], code].whereType<String>().join(' · ');
      case 'Audio':
        return artists.isNotEmpty ? artists.join(', ') : albumArtist;
      case 'MusicAlbum':
        return albumArtist;
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
  String get name => (_j['Name'] as String?)?.trim() ?? '';

  Map<String, dynamic>? get _video => ((_j['MediaStreams'] as List?) ?? const [])
      .cast<Map<String, dynamic>>()
      .where((s) => s['Type'] == 'Video')
      .firstOrNull;

  /// "4K", "1080p"...; what the app remembers to pick the same kind of file next time.
  String? get resolution {
    final video = _video;
    return video == null ? null : _resolution((video['Width'] as num?)?.toInt(), (video['Height'] as num?)?.toInt());
  }

  /// "4K · HEVC · Dolby Vision · 58.2 GB", without what [name] already says.
  String get details {
    final video = _video;
    final parts = [
      if (video != null) ...[
        resolution,
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

/// The version to play without asking: the first in the server's order with the remembered
/// resolution, or null to let the user choose.
MediaVersion? chooseVersion(List<MediaVersion> versions, String? resolution) =>
    resolution == null ? null : versions.where((v) => v.resolution == resolution).firstOrNull;

class JellyfinClient {
  JellyfinClient(this.account, this.deviceId, {http.Client? client}) : _http = client ?? http.Client();

  final Account account;
  final String deviceId;
  final http.Client _http;

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
    final res = await _http.get(uri, headers: headers).timeout(_timeout);
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
        'fields': 'PrimaryImageAspectRatio,MediaSourceCount,Path',
        'enableImageTypes': 'Primary',
        'enableUserData': 'true',
        // Episodes and seasons Jellyfin knows from online metadata but has no files for.
        // Jellyfin 12 does not always honour these filters, so they are dropped below too.
        'excludeLocationTypes': 'Virtual',
        'isMissing': 'false',
      }))
          .where((i) => !i.isVirtual)
          .toList();

  /// Fields the home screen and the details page show.
  static const _richFields =
      'PrimaryImageAspectRatio,MediaSourceCount,Overview,Genres,ProductionYear,ParentBackdropItemId,'
      'BackdropImageTags';

  Future<List<JellyfinItem>> _list(String path, Map<String, String> query) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final res = await _http.get(uri, headers: headers).timeout(_timeout);
    if (res.statusCode == 401) throw ApiException('Session expired. Remove the server and sign in again.');
    if (res.statusCode != 200) throw ApiException('Server answered ${res.statusCode} for $path');
    final body = jsonDecode(res.body);
    // /Items/Latest answers with a bare list, the others with {Items: [...]}.
    final raw = body is List ? body : ((body as Map<String, dynamic>)['Items'] as List?) ?? const [];
    return [for (final e in raw) JellyfinItem(e as Map<String, dynamic>)];
  }

  /// Movies and episodes started and not finished, latest first.
  Future<List<JellyfinItem>> resume({int limit = 16}) => _list('/UserItems/Resume', {
        'userId': account.userId!,
        'limit': '$limit',
        'mediaTypes': 'Video',
        'fields': _richFields,
        'enableUserData': 'true',
      });

  /// The next episode of each series being watched.
  Future<List<JellyfinItem>> nextUp({int limit = 16}) => _list('/Shows/NextUp', {
        'userId': account.userId!,
        'limit': '$limit',
        'fields': _richFields,
        'enableUserData': 'true',
      });

  /// Newest in a library: movies, series (not single episodes), albums.
  Future<List<JellyfinItem>> latest(String libraryId, {int limit = 16}) => _list('/Items/Latest', {
        'userId': account.userId!,
        'parentId': libraryId,
        'limit': '$limit',
        'fields': _richFields,
        'enableUserData': 'true',
        'groupItems': 'true',
      });

  /// One item with everything the details page shows.
  Future<JellyfinItem> item(String id) async => JellyfinItem(await _get('/Items/$id', {
        'userId': account.userId!,
        'fields': '$_richFields,People,Studios,Taglines',
      }));

  Future<List<JellyfinItem>> seasons(String seriesId) async => (await _list('/Shows/$seriesId/Seasons', {
        'userId': account.userId!,
        'fields': _richFields,
        'enableUserData': 'true',
      }))
          .where((i) => !i.isVirtual)
          .toList();

  Future<List<JellyfinItem>> episodes(String seriesId, String seasonId) async => (await _list('/Shows/$seriesId/Episodes', {
        'userId': account.userId!,
        'seasonId': seasonId,
        'fields': _richFields,
        'enableUserData': 'true',
      }))
          .where((i) => !i.isVirtual)
          .toList();

  /// A page of a library as posters: [types] like 'Movie' or 'Series', sorted by [sort].
  Future<({List<JellyfinItem> items, int total})> libraryPage(String libraryId,
      {required String types, required LibrarySort sort, int start = 0, int limit = 60}) async {
    final j = await _get('/Items', {
      'userId': account.userId!,
      'parentId': libraryId,
      'recursive': 'true',
      'includeItemTypes': types,
      'sortBy': sort.sortBy,
      'sortOrder': sort.descending ? 'Descending' : 'Ascending',
      'startIndex': '$start',
      'limit': '$limit',
      'fields': 'PrimaryImageAspectRatio,MediaSourceCount,ProductionYear',
      'enableUserData': 'true',
      'excludeLocationTypes': 'Virtual',
    });
    return (items: _items(j).where((i) => !i.isVirtual).toList(), total: (j['TotalRecordCount'] as num?)?.toInt() ?? 0);
  }

  /// Every track of a music library, page by page: the music screen sorts and groups them
  /// itself, so it works also where the server has no albums for loose files.
  Future<List<JellyfinItem>> musicTracks(String libraryId) =>
      _allPages({'parentId': libraryId, 'recursive': 'true', 'includeItemTypes': 'Audio'});

  /// Every file the search can find by its name on disk: videos, tracks and photos, with
  /// their paths. The server's own search looks at titles only.
  Future<List<JellyfinItem>> allFiles() =>
      _allPages({'recursive': 'true', 'includeItemTypes': 'Movie,Episode,Video,MusicVideo,Audio,Photo'});

  /// A music artist's tracks, by the server's artist id (from the search).
  Future<List<JellyfinItem>> artistTracks(String artistId) =>
      _allPages({'artistIds': artistId, 'recursive': 'true', 'includeItemTypes': 'Audio'});

  /// An album's tracks, in disc and track order.
  Future<List<JellyfinItem>> albumTracks(String albumId) => _allPages({
        'parentId': albumId,
        'recursive': 'true',
        'includeItemTypes': 'Audio',
        'sortBy': 'ParentIndexNumber,IndexNumber,SortName',
      });

  Future<List<JellyfinItem>> _allPages(Map<String, String> query, {int page = 2000}) async {
    final all = <JellyfinItem>[];
    while (true) {
      final j = await _get('/Items', {
        'userId': account.userId!,
        'fields': 'DateCreated,Genres,MediaSourceCount,Path',
        'enableUserData': 'true',
        'excludeLocationTypes': 'Virtual',
        'startIndex': '${all.length}',
        'limit': '$page',
        ...query,
      });
      final items = _items(j);
      all.addAll(items);
      final total = (j['TotalRecordCount'] as num?)?.toInt() ?? all.length;
      if (items.isEmpty || all.length >= total) return all;
    }
  }

  // --- Playlists ---

  /// The user's playlists, by name.
  Future<List<JellyfinItem>> playlists() async => _items(await _get('/Items', {
        'userId': account.userId!,
        'includeItemTypes': 'Playlist',
        'recursive': 'true',
        'sortBy': 'SortName',
        'fields': 'ChildCount,DateCreated',
      }));

  /// A playlist's entries in their order; each carries its [JellyfinItem.playlistEntryId].
  Future<List<JellyfinItem>> playlistItems(String playlistId) async =>
      _items(await _get('/Playlists/$playlistId/Items', {'userId': account.userId!, 'fields': 'MediaSourceCount,Path'}));

  /// A new playlist with [ids] in it; its id.
  Future<String> createPlaylist(String name, List<String> ids, {String mediaType = 'Audio'}) async {
    final j = await _send('POST', '/Playlists', body: {
      'Name': name,
      'Ids': ids,
      'UserId': account.userId,
      'MediaType': mediaType,
    });
    return (j?['Id'] as String?) ?? '';
  }

  Future<void> addToPlaylist(String playlistId, List<String> ids) =>
      _send('POST', '/Playlists/$playlistId/Items', query: {'ids': ids.join(','), 'userId': account.userId!});

  Future<void> removeFromPlaylist(String playlistId, List<String> entryIds) =>
      _send('DELETE', '/Playlists/$playlistId/Items', query: {'entryIds': entryIds.join(',')});

  Future<void> deletePlaylist(String playlistId) => _send('DELETE', '/Items/$playlistId');

  // --- Search ---

  /// Items matching [filters]; artists come from their own list on the server.
  Future<List<JellyfinItem>> search(SearchFilters filters) async {
    final userId = account.userId!;
    final artists = filters.wantsArtists || filters.byArtist
        ? _get('/Artists', filters.artistsQuery(userId)).then(_items)
        : Future.value(const <JellyfinItem>[]);
    final byName = filters.kind.types != null ? _get('/Items', filters.itemsQuery(userId)).then(_items) : null;
    final found = await artists;
    // "danheim" with Tracks: the server's word search looks at track names only.
    final byArtist = filters.byArtist && found.isNotEmpty
        ? _get('/Items', filters.byArtistQuery(userId, [for (final a in found.take(10)) a.id])).then(_items)
        : null;
    final seen = <String>{};
    return [
      if (filters.wantsArtists) ...found,
      if (byName != null) ...await byName,
      if (byArtist != null) ...await byArtist,
    ].where((i) => seen.add(i.id)).toList();
  }

  /// Genres to pick from in the search filters.
  Future<List<String>> genres() async => [
        for (final g in _items(await _get('/Genres', {'userId': account.userId!, 'recursive': 'true', 'sortBy': 'SortName'})))
          if (g.name.isNotEmpty) g.name,
      ];

  /// A request that changes something on the server; the answer, when there is one.
  Future<Map<String, dynamic>?> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final req = http.Request(method, Uri.parse('$_base$path').replace(queryParameters: query))
      ..headers.addAll({...headers, 'Content-Type': 'application/json'});
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req).timeout(_timeout));
    if (res.statusCode == 401) throw ApiException('Session expired. Remove the server and sign in again.');
    if (res.statusCode == 403) throw ApiException('The server does not allow this for your user.');
    if (res.statusCode >= 300) throw ApiException('Server answered ${res.statusCode} for $path');
    if (res.body.isEmpty) return null;
    final j = jsonDecode(res.body);
    return j is Map<String, dynamic> ? j : null;
  }

  /// How many items of [types] a library holds, without fetching them.
  Future<int> count(String libraryId, String types) async {
    final j = await _get('/Items', {
      'userId': account.userId!,
      'parentId': libraryId,
      'recursive': 'true',
      'includeItemTypes': types,
      'limit': '0',
      'enableTotalRecordCount': 'true',
      'isMissing': 'false',
    });
    return (j['TotalRecordCount'] as num?)?.toInt() ?? 0;
  }

  /// A wide picture for [item]: its own backdrop, its series', or for an episode its still.
  Uri? backdropUrl(JellyfinItem item, {int width = 1280}) {
    final owner = item.backdropOwner;
    if (owner == null) return null;
    return Uri.parse('$_base/Items/$owner/Images/Backdrop').replace(queryParameters: {'maxWidth': '$width', 'quality': '85'});
  }

  /// A 16:9 picture for a card: an episode's still, else the backdrop, else nothing.
  Uri? wideUrl(JellyfinItem item, {int width = 640}) {
    if (item.type == 'Episode' && item.hasPrimaryImage) {
      return Uri.parse('$_base/Items/${item.id}/Images/Primary').replace(queryParameters: {'maxWidth': '$width', 'quality': '85'});
    }
    if (item.hasThumb) {
      return Uri.parse('$_base/Items/${item.id}/Images/Thumb').replace(queryParameters: {'maxWidth': '$width', 'quality': '85'});
    }
    return backdropUrl(item, width: width);
  }

  /// Tracks matching [query], for voice search in the car.
  Future<List<JellyfinItem>> searchAudio(String query) async => _items(await _get('/Items', {
        'userId': account.userId!,
        'searchTerm': query,
        'includeItemTypes': 'Audio',
        'recursive': 'true',
        'limit': '50',
        'enableImageTypes': 'Primary',
      }));

  /// Everything playable under a folder (a series, a season, an album), in play order, for
  /// downloading it whole.
  Future<List<JellyfinItem>> playableDescendants(String parentId) async => _items(await _get('/Items', {
        'userId': account.userId!,
        'parentId': parentId,
        'recursive': 'true',
        'mediaTypes': 'Video,Audio',
        'sortBy': 'ParentIndexNumber,IndexNumber,SortName',
        'sortOrder': 'Ascending',
        'enableImageTypes': 'Primary',
        'excludeLocationTypes': 'Virtual',
        'isMissing': 'false',
      }))
          .where((i) => i.isPlayable && !i.isVirtual)
          .toList();

  /// The item's own picture or, for a track without one, its album's cover.
  Uri? imageUrl(JellyfinItem item, {int height = 300}) {
    final owner = item.hasPrimaryImage ? item.id : item.albumImageOwner;
    return owner == null
        ? null
        : Uri.parse('$_base/Items/$owner/Images/Primary')
            .replace(queryParameters: {'fillHeight': '$height', 'quality': '90'});
  }

  /// A photo scaled by the server to fit [maxSide] pixels; the original may be far larger
  /// than the screen. Jellyfin applies the EXIF rotation.
  Uri photoUrl(JellyfinItem item, {required int maxSide}) =>
      Uri.parse('$_base/Items/${item.id}/Images/Primary').replace(queryParameters: {
        'maxWidth': '$maxSide',
        'maxHeight': '$maxSide',
        'quality': '90',
      });

  /// Direct play: the file goes to mpv untouched. Transcoding comes later,
  /// for slow mobile connections. [versionId] picks one of several files; null is the default.
  /// The original file as it lies on the server, for saving it to the phone.
  Uri originalFileUrl(JellyfinItem item) => Uri.parse('$_base/Items/${item.id}/Download');

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
        // The first codec is what a bitrate cap converts to: H.264 every server encodes fast.
        // The rest only allow copying the video when just the audio is converted.
        'VideoCodec': 'h264,hevc,av1,vp9',
        'AudioCodec': 'aac,eac3,ac3',
        'MaxAudioChannels': '6',
        'MinSegments': 1,
        'BreakOnNonKeyFrames': true,
      },
    ],
    // Every subtitle format is fine inside the file: without this the server may burn them in.
    // Text subtitles can also come as separate files: .srt/.ass next to the video, and the
    // text subtitles of a video the server converts (a converted stream carries none).
    'SubtitleProfiles': [
      for (final f in ['ass', 'ssa', 'srt', 'subrip', 'vtt', 'webvtt', 'pgssub', 'dvdsub', 'dvbsub', 'mov_text'])
        {'Format': f, 'Method': 'Embed'},
      for (final f in ['ass', 'ssa', 'srt', 'subrip', 'vtt', 'webvtt']) {'Format': f, 'Method': 'External'},
    ],
  };

  /// Subtitle files the server delivers apart from the video, from a PlaybackInfo media source.
  List<ExternalSubtitle> deliveredSubtitles(Map<String, dynamic> source) => [
        for (final s in _streams(source, 'Subtitle'))
          if (s['DeliveryMethod'] == 'External' && s['DeliveryUrl'] is String)
            ExternalSubtitle(
              url: _withKey(Uri.parse('$_base${s['DeliveryUrl']}')),
              title: (s['Title'] as String?) ?? (s['IsExternal'] == true ? 'External' : null),
              language: s['Language'] as String?,
            ),
      ];

  /// Subtitles of [source] the player gets neither inside the stream nor as a file: picture
  /// subtitles of a converted video.
  bool losesSubtitles(Map<String, dynamic> source) =>
      _streams(source, 'Subtitle').any((s) => s['DeliveryMethod'] != 'External');

  static Iterable<Map<String, dynamic>> _streams(Map<String, dynamic> source, String type) =>
      ((source['MediaStreams'] as List?) ?? const []).cast<Map<String, dynamic>>().where((s) => s['Type'] == type);

  /// mpv fetches subtitle files on its own, without our headers, so the token rides in the URL.
  Uri _withKey(Uri url) => url.queryParameters.keys.any((k) => k.toLowerCase() == 'api_key' || k == 'ApiKey')
      ? url
      : url.replace(queryParameters: {...url.queryParameters, 'ApiKey': account.token!});

  /// The bitrate cap for [quality] on the connection right now; Auto measures it.
  Future<int?> capNow(VideoQuality quality) async =>
      capFor(quality, measured: quality.isAuto ? await measureBitrate() : null);

  /// Speed to the server in bit/s, from timing a download of test bytes; null if it fails.
  /// A second, larger download on fast links, where the first is too short to time.
  Future<double?> measureBitrate() async {
    Future<double> time(int size) async {
      final watch = Stopwatch()..start();
      final res = await _http
          .get(Uri.parse('$_base/Playback/BitrateTest').replace(queryParameters: {'size': '$size'}), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw ApiException('Server answered ${res.statusCode} for BitrateTest');
      return res.bodyBytes.length * 8 / (watch.elapsedMicroseconds / 1e6);
    }

    try {
      final first = await time(500 * 1000);
      return first > 20e6 ? await time(4 * 1000 * 1000) : first;
    } catch (e) {
      debugPrint('homeplay bitrate test failed: $e');
      return null;
    }
  }

  /// Direct play when the phone can decode the audio; otherwise another audio track in the
  /// file, and only as a last resort audio converted by the server. [versionId] picks one of
  /// several files of the item; null is the server's default. A file above [cap] (bit/s) is
  /// converted by the server to fit it.
  Future<PlayItem> resolve(JellyfinItem item, {String? versionId, int? cap}) async {
    final direct = toPlayItem(item, versionId: versionId);
    if (!item.isVideo) return direct;
    Future<PlayItem> again(VideoQuality q) async => resolve(item, versionId: versionId, cap: await capNow(q));

    final version = {'MediaSourceId': ?versionId};
    final info = await _playbackInfo(item.id, version);
    final sources = ((info['MediaSources'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final source = sources.where((s) => s['Id'] == versionId).firstOrNull ?? sources.firstOrNull;
    if (source == null) return direct;
    final played = direct.copyWith(
      reporter: _reporter(item, source['Id'] as String?, info['PlaySessionId'] as String?, 'DirectPlay'),
      withQuality: again,
      subtitles: deliveredSubtitles(source),
    );

    if (needsConversion((source['Bitrate'] as num?)?.toInt(), cap)) {
      return _convert(item, direct, version, cap!, source, again);
    }

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
      notice: '$wanted isn\'t supported on this phone, so the server converts the sound.'
          '${convertedSource != null && losesSubtitles(convertedSource) ? ' Picture subtitles are off in this mode.' : ''}',
      // Its stop report also ends the conversion on the server.
      reporter: _reporter(item, convertedSource?['Id'] as String?, converted['PlaySessionId'] as String?, 'Transcode'),
      withQuality: again,
      subtitles: convertedSource == null ? const [] : deliveredSubtitles(convertedSource),
    );
  }

  /// The whole file converted by the server under [cap]: video re-encoded at a lower bitrate
  /// (and size), audio to AAC; the default audio track is kept.
  Future<PlayItem> _convert(JellyfinItem item, PlayItem direct, Map<String, dynamic> version, int cap,
      Map<String, dynamic> source, Future<PlayItem> Function(VideoQuality) again) async {
    final converted = await _playbackInfo(item.id, {
      ...version,
      'MaxStreamingBitrate': cap,
      'AudioStreamIndex': ?source['DefaultAudioStreamIndex'],
      'EnableDirectPlay': false,
      'EnableDirectStream': false,
      'AllowVideoStreamCopy': false,
    });
    final convertedSource = ((converted['MediaSources'] as List?) ?? const []).cast<Map<String, dynamic>>().firstOrNull;
    final url = convertedSource?['TranscodingUrl'] as String?;
    debugPrint('homeplay conversion to ${bitrateLabel(cap)} for ${item.name}: ${url == null ? 'refused' : 'ok'}');
    if (url == null) {
      return direct.copyWith(
        notice: 'The server can\'t convert this video, so it plays as it is and may stutter',
        withQuality: again,
      );
    }
    return direct.copyWith(
      url: Uri.parse('$_base$url'),
      notice: 'Converted by the server to ${bitrateLabel(cap)} for this connection.'
          '${losesSubtitles(convertedSource!) ? ' Picture subtitles are off in this mode.' : ''}',
      reporter: _reporter(item, convertedSource['Id'] as String?, converted['PlaySessionId'] as String?, 'Transcode'),
      convertedTo: cap,
      withQuality: again,
      subtitles: deliveredSubtitles(convertedSource),
    );
  }

  Future<Map<String, dynamic>> _playbackInfo(String itemId, Map<String, dynamic> overrides) async {
    final res = await _http
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
      await _http
          .post(Uri.parse('$_base$path'),
              headers: {...headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_timeout);
    } catch (e) {
      debugPrint('homeplay report $path failed: $e');
    }
  }

  /// What was played of a download, sent once there is a connection: a stop report on its
  /// own, from which the server sets the resume point or the played mark as after streaming.
  /// False when the server did not take it, so it is sent again later.
  Future<bool> reportPlayed(String itemId, Duration position) async {
    try {
      final res = await _http
          .post(Uri.parse('$_base/Sessions/Playing/Stopped'),
              headers: {...headers, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'ItemId': itemId,
                'MediaSourceId': itemId,
                'PlayMethod': 'DirectPlay',
                'PositionTicks': position.inMicroseconds * 10,
              }))
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('homeplay played report for a download failed: $e');
      return false;
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
  Future<void> stopped(Duration position, {Duration? duration}) =>
      _client._report('/Sessions/Playing/Stopped', _body(position));
}

/// How a library grid is sorted.
enum LibrarySort {
  name('Name', 'SortName', false),
  added('Date added', 'DateCreated,SortName', true),
  year('Year', 'ProductionYear,PremiereDate,SortName', true),
  rating('Rating', 'CommunityRating,SortName', true);

  const LibrarySort(this.label, this.sortBy, this.descending);
  final String label;
  final String sortBy;
  final bool descending;
}

/// What a library grid shows for a library of [collectionType]; null for libraries better
/// browsed as folders (home videos, photos, mixed).
String? posterTypes(String? collectionType) => switch (collectionType) {
      'movies' => 'Movie',
      'tvshows' => 'Series',
      'music' => 'MusicAlbum',
      'musicvideos' => 'MusicVideo',
      'boxsets' => 'BoxSet',
      _ => null,
    };

/// "2 h 15 min", "48 min", "20 s".
String runTimeLabel(Duration d) {
  if (d < const Duration(minutes: 1)) return '${d.inSeconds} s';
  final h = d.inHours, m = d.inMinutes.remainder(60);
  return h > 0 ? (m > 0 ? '$h h $m min' : '$h h') : '${d.inMinutes} min';
}

/// The number a file name starts with, as in "01-Cluster One.mp3" or "3. Time.flac"; null when
/// it does not start with one, or the number looks like a year.
int? trackNumberFromPath(String? path) {
  if (path == null) return null;
  final name = path.split(RegExp(r'[/\\]')).last;
  final m = RegExp(r'^(\d{1,3})(?:[\s._\-)]|$)').firstMatch(name);
  return m == null ? null : int.parse(m.group(1)!);
}
