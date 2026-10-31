import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/jellyfin.dart';

/// The tracks of a music library kept on the phone, so the music screen shows them at once,
/// also after the app was closed and without a connection, while a fresh list comes from the
/// server. One file per server, user and library, in the app's private folder; it holds the
/// server's records as they came (names, albums, file paths), never a token.
class LibraryCache {
  LibraryCache._();

  /// What was read or written while the app runs: opening the library again costs nothing.
  static final Map<String, List<JellyfinItem>> _memory = {};

  /// Off in widget tests: their clock is fake, and real file reads there never finish.
  @visibleForTesting
  static bool enabled = true;

  /// The name of a library's file: a folder for the server and user, a file for the library.
  static String key({required String baseUrl, required String userId, required String libraryId}) =>
      '${_accountFolder(baseUrl, userId)}/${sha1.convert(utf8.encode(libraryId))}';

  static String _accountFolder(String baseUrl, String userId) => sha1.convert(utf8.encode('$baseUrl|$userId')).toString();

  /// Forgets every library of a server removed from the app: nothing of it stays on the phone.
  static Future<void> forget({required String baseUrl, required String userId}) async {
    final folder = _accountFolder(baseUrl, userId);
    _memory.removeWhere((key, _) => key.startsWith('$folder/'));
    if (!enabled) return;
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/music_cache/$folder');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('homeplay music cache forget failed: $e');
    }
  }

  static Future<File> _file(String key) async =>
      File('${(await getApplicationSupportDirectory()).path}/music_cache/$key.json');

  /// The tracks read or written for [key] while the app runs; null before that.
  static List<JellyfinItem>? inMemory(String key) => enabled ? _memory[key] : null;

  /// Remembers [tracks] read in another isolate (see [readFile]) for this run.
  static void remember(String key, List<JellyfinItem> tracks) {
    if (enabled) _memory[key] = tracks;
  }

  /// Where [key]'s file is, for [readFile] in another isolate; null when there is none.
  static Future<String?> pathOf(String key) async {
    if (!enabled) return null;
    try {
      final file = await _file(key);
      return await file.exists() ? file.path : null;
    } catch (e) {
      debugPrint('homeplay music cache: $e');
      return null;
    }
  }

  /// The tracks in the file at [path]; null when it cannot be read. Synchronous, for a
  /// background isolate: a big library is megabytes of text.
  static List<JellyfinItem>? readFile(String path) {
    try {
      final records = decodeTracks(File(path).readAsStringSync());
      return records == null ? null : [for (final r in records) JellyfinItem(r)];
    } catch (_) {
      return null;
    }
  }

  /// The tracks kept for [key]; null when there are none or the file cannot be read.
  static Future<List<JellyfinItem>?> read(String key) async {
    final known = inMemory(key);
    if (known != null) return known;
    final path = await pathOf(key);
    if (path == null) return null;
    final tracks = await Isolate.run(() => readFile(path));
    if (tracks != null) remember(key, tracks);
    return tracks;
  }

  /// Keeps [tracks] for [key]. A failed write only means the next start loads from the server.
  static Future<void> write(String key, List<JellyfinItem> tracks) async {
    if (!enabled) return;
    _memory[key] = tracks;
    try {
      final file = await _file(key);
      await file.parent.create(recursive: true);
      final records = [for (final t in tracks) slimTrack(t.raw)];
      final text = await Isolate.run(() => encodeTracks(records, DateTime.now()));
      // Whole or not at all: a phone switched off mid-write leaves the old file.
      final part = File('${file.path}.part');
      await part.writeAsString(text, flush: true);
      await part.rename(file.path);
    } catch (e) {
      debugPrint('homeplay music cache write failed: $e');
    }
  }
}

/// The version of the file's layout; a file of another one is ignored and made again.
const libraryCacheVersion = 2;

/// The parts of a server record the app reads (JellyfinItem's getters). The rest (picture
/// blur hashes, ids of the server and channel, the same artists again as objects...) is most of
/// the size and is not kept. A getter reading a new part needs it added here and the version up.
const _kept = {
  'Album', 'AlbumArtist', 'AlbumId', 'AlbumPrimaryImageTag', 'Artists', 'BackdropImageTags', 'ChildCount',
  'CollectionType', 'CommunityRating', 'Container', 'DateCreated', 'Genres', 'Id', 'ImageTags', 'IndexNumber',
  'IsFolder', 'LocationType', 'MediaSourceCount', 'MediaStreams', 'MediaType', 'Name', 'OfficialRating', 'Overview',
  'ParentBackdropItemId', 'ParentIndexNumber', 'Path', 'PlaylistItemId', 'PrimaryImageAspectRatio', 'ProductionYear',
  'RunTimeTicks', 'SeasonId', 'SeriesId', 'SeriesName', 'Size', 'Type', 'UserData',
};

/// [record] with only what the app reads.
Map<String, dynamic> slimTrack(Map<String, dynamic> record) => {
      for (final e in record.entries)
        if (_kept.contains(e.key) && e.value != null) e.key: e.value,
    };

/// The file's text for [records] (the server's track records) kept at [savedAt].
String encodeTracks(List<Map<String, dynamic>> records, DateTime savedAt) =>
    jsonEncode({'v': libraryCacheVersion, 'savedAt': savedAt.toIso8601String(), 'items': records});

/// The track records in a file's [text]; null when it is not a file of this layout.
List<Map<String, dynamic>>? decodeTracks(String text) {
  try {
    final j = jsonDecode(text);
    if (j is! Map || j['v'] != libraryCacheVersion || j['items'] is! List) return null;
    return [
      for (final r in j['items'] as List)
        if (r is Map<String, dynamic> && r['Id'] is String) r,
    ];
  } catch (_) {
    return null;
  }
}
