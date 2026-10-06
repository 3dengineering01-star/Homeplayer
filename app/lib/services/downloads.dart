import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';

enum DownloadState { queued, running, paused, done, failed }

/// A subtitle file saved next to a download.
class SavedSubtitle {
  const SavedSubtitle({required this.file, this.title, this.language});

  factory SavedSubtitle.fromJson(Map<String, dynamic> j) =>
      SavedSubtitle(file: j['file'] as String, title: j['title'] as String?, language: j['language'] as String?);

  final String file;
  final String? title;
  final String? language;

  Map<String, dynamic> toJson() => {'file': file, 'title': title, 'language': language};
}

/// One movie, episode or track kept on the phone. Files are named after [id] inside the
/// downloads folder, so nothing from the server ends up in a path.
class DownloadEntry {
  const DownloadEntry({
    required this.id,
    required this.title,
    required this.isVideo,
    this.subtitle,
    this.group,
    this.hasArtwork = false,
    this.subtitles = const [],
    this.state = DownloadState.queued,
    this.progress = 0,
    this.size = 0,
  });

  factory DownloadEntry.fromJson(Map<String, dynamic> j) => DownloadEntry(
        id: j['id'] as String,
        title: j['title'] as String,
        isVideo: j['isVideo'] as bool,
        subtitle: j['subtitle'] as String?,
        group: j['group'] as String?,
        hasArtwork: j['hasArtwork'] as bool? ?? false,
        subtitles: [for (final s in (j['subtitles'] as List? ?? const [])) SavedSubtitle.fromJson(s as Map<String, dynamic>)],
        state: DownloadState.values.byName(j['state'] as String),
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        size: (j['size'] as num?)?.toInt() ?? 0,
      );

  /// Jellyfin item id; unique enough across servers for one phone.
  final String id;
  final String title;
  final String? subtitle;

  /// Season or album it came with, for grouping on the downloads screen.
  final String? group;
  final bool isVideo;
  final bool hasArtwork;
  final List<SavedSubtitle> subtitles;
  final DownloadState state;

  /// 0..1 while downloading.
  final double progress;

  /// Bytes, once known.
  final int size;

  String get file => 'media_$id';
  String get artworkFile => 'art_$id';

  DownloadEntry copyWith({DownloadState? state, double? progress, int? size}) => DownloadEntry(
        id: id,
        title: title,
        isVideo: isVideo,
        subtitle: subtitle,
        group: group,
        hasArtwork: hasArtwork,
        subtitles: subtitles,
        state: state ?? this.state,
        progress: progress ?? this.progress,
        size: size ?? this.size,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'group': group,
        'isVideo': isVideo,
        'hasArtwork': hasArtwork,
        'subtitles': [for (final s in subtitles) s.toJson()],
        'state': state.name,
        'progress': progress,
        'size': size,
      };
}

/// The state background_downloader reports, in the app's terms.
DownloadState stateOf(TaskStatus status) => switch (status) {
      TaskStatus.enqueued || TaskStatus.waitingToRetry => DownloadState.queued,
      TaskStatus.running => DownloadState.running,
      TaskStatus.paused => DownloadState.paused,
      TaskStatus.complete => DownloadState.done,
      TaskStatus.notFound || TaskStatus.failed || TaskStatus.canceled => DownloadState.failed,
    };

/// "1.4 GB", "350 MB".
String sizeLabel(int bytes) {
  const mb = 1024 * 1024, gb = mb * 1024;
  return bytes >= gb ? '${(bytes / gb).toStringAsFixed(1)} GB' : '${(bytes / mb).round()} MB';
}

/// Movies, episodes and tracks downloaded to the phone for playing without a connection.
/// The big file goes through background_downloader (keeps going with the app closed,
/// resumes after a dropped connection); subtitle files and artwork are small and fetched at once.
class Downloads {
  Downloads._();

  static final instance = Downloads._();

  /// In the order they were added, so a season or an album keeps its play order.
  final ValueNotifier<List<DownloadEntry>> entries = ValueNotifier(const []);

  late Directory _dir;
  bool _started = false;

  File get _index => File('${_dir.path}/downloads.json');

  Future<void> init() async {
    if (_started) return;
    _started = true;
    _dir = Directory('${(await getApplicationSupportDirectory()).path}/downloads');
    await _dir.create(recursive: true);
    if (await _index.exists()) {
      try {
        entries.value = [
          for (final e in jsonDecode(await _index.readAsString()) as List) DownloadEntry.fromJson(e as Map<String, dynamic>),
        ];
      } catch (e) {
        debugPrint('homeplay downloads index unreadable: $e');
      }
    }
    FileDownloader().configureNotification(
      running: const TaskNotification('{displayName}', 'Downloading · {progress}'),
      complete: const TaskNotification('{displayName}', 'Downloaded'),
      error: const TaskNotification('{displayName}', 'Download failed'),
      progressBar: true,
    );
    FileDownloader().updates.listen(_onUpdate);
    await FileDownloader().start();
  }

  DownloadEntry? find(String itemId) => entries.value.where((e) => e.id == itemId).firstOrNull;

  String pathOf(String file) => '${_dir.path}/$file';

  /// Queues [items] (playable ones not on the phone yet). Returns how many were added.
  Future<int> add(JellyfinClient client, List<JellyfinItem> items, {String? group}) async {
    await init();
    if (Platform.isAndroid) await FileDownloader().permissions.request(PermissionType.notifications);
    var added = 0;
    for (final item in items.where((i) => i.isPlayable && find(i.id) == null)) {
      final entry = await _sidecars(client, item, group);
      _put(entry);
      final ok = await FileDownloader().enqueue(DownloadTask(
        taskId: item.id,
        url: client.streamUrl(item).toString(),
        headers: client.headers,
        baseDirectory: BaseDirectory.applicationSupport,
        directory: 'downloads',
        filename: entry.file,
        displayName: item.name,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: 3,
        // User-initiated transfer on Android 14+: no 9-minute limit for a long movie.
        priority: 0,
      ));
      if (!ok) _put(entry.copyWith(state: DownloadState.failed));
      added++;
    }
    await _save();
    return added;
  }

  /// Artwork and subtitle files next to the video; a missing one is no reason to fail.
  Future<DownloadEntry> _sidecars(JellyfinClient client, JellyfinItem item, String? group) async {
    final id = item.id;
    var hasArtwork = false;
    final art = client.imageUrl(item, height: 600);
    if (art != null) hasArtwork = await _fetch(art, client.headers, 'art_$id');
    final subtitles = <SavedSubtitle>[];
    if (item.isVideo) {
      try {
        final played = await client.resolve(item);
        for (final (n, s) in played.subtitles.indexed) {
          final file = 'sub_${id}_$n';
          if (await _fetch(s.url, const {}, file)) {
            subtitles.add(SavedSubtitle(file: file, title: s.title, language: s.language));
          }
        }
      } catch (e) {
        debugPrint('homeplay download: no subtitle list for ${item.name}: $e');
      }
    }
    return DownloadEntry(
      id: id,
      title: item.name,
      subtitle: item.subtitle,
      group: group,
      isVideo: item.isVideo,
      hasArtwork: hasArtwork,
      subtitles: subtitles,
    );
  }

  Future<bool> _fetch(Uri url, Map<String, String> headers, String file) async {
    try {
      final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return false;
      await File(pathOf(file)).writeAsBytes(res.bodyBytes);
      return true;
    } catch (e) {
      debugPrint('homeplay download: $file failed: $e');
      return false;
    }
  }

  /// Stops a download if it runs and deletes its files.
  Future<void> remove(String id) async {
    final entry = find(id);
    if (entry == null) return;
    await FileDownloader().cancelTaskWithId(id);
    for (final f in [entry.file, entry.artworkFile, for (final s in entry.subtitles) s.file]) {
      final file = File(pathOf(f));
      if (await file.exists()) await file.delete();
    }
    entries.value = entries.value.where((e) => e.id != id).toList();
    await _save();
  }

  void _put(DownloadEntry entry) {
    final at = entries.value.indexWhere((e) => e.id == entry.id);
    entries.value = at < 0 ? [...entries.value, entry] : ([...entries.value]..[at] = entry);
  }

  void _onUpdate(TaskUpdate update) {
    final entry = find(update.task.taskId);
    if (entry == null) return;
    switch (update) {
      case TaskStatusUpdate(:final status):
        final state = stateOf(status);
        _put(entry.copyWith(state: state, progress: state == DownloadState.done ? 1 : null));
        if (state == DownloadState.done) _measure(entry.id);
        unawaited(_save());
      case TaskProgressUpdate(:final progress, :final expectedFileSize):
        // Negative progress values are status codes of the library, not fractions.
        if (progress >= 0 && progress <= 1) {
          _put(entry.copyWith(
            state: DownloadState.running,
            progress: progress,
            size: expectedFileSize > 0 ? expectedFileSize : null,
          ));
        }
    }
  }

  Future<void> _measure(String id) async {
    final file = File(pathOf('media_$id'));
    if (!await file.exists()) return;
    final size = await file.length();
    final entry = find(id);
    if (entry != null) _put(entry.copyWith(size: size));
    await _save();
  }

  Future<void> _save() async {
    try {
      await _index.writeAsString(jsonEncode([for (final e in entries.value) e.toJson()]));
    } catch (e) {
      debugPrint('homeplay downloads index not saved: $e');
    }
  }

  PlayItem toPlayItem(DownloadEntry e) => downloadedPlayItem(e, _dir.path);
}

/// What the player opens for a download kept in [dir]: local files only, nothing reported
/// to the server.
PlayItem downloadedPlayItem(DownloadEntry e, String dir) => PlayItem(
      title: e.title,
      subtitle: e.subtitle,
      url: Uri.file('$dir/${e.file}'),
      artwork: e.hasArtwork ? Uri.file('$dir/${e.artworkFile}') : null,
      isVideo: e.isVideo,
      subtitles: [
        for (final s in e.subtitles) ExternalSubtitle(url: Uri.file('$dir/${s.file}'), title: s.title, language: s.language),
      ],
    );
