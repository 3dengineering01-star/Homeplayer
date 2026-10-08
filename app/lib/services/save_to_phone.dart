import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';

import '../api/jellyfin.dart';
import 'downloads.dart';
import 'music_index.dart';

/// Tracks saved as ordinary files in the phone's Music folder, Music/Homeplay/artist/album,
/// where any player, the ringtone picker or a file manager finds them. Unlike Downloads, which
/// keep tracks inside the app for listening without a connection, these leave the app: the
/// original file from the server, under its own name.
class SaveToPhone {
  SaveToPhone._();

  /// The download group of these files, apart from the app's own downloads.
  static const group = 'save-to-phone';

  /// Queues [tracks] (non-tracks are skipped); each one moves into the Music folder when it
  /// is down. Returns how many were queued.
  static Future<int> save(JellyfinClient client, List<JellyfinItem> tracks) async {
    final audio = tracks.where((t) => t.type == 'Audio').toList();
    if (audio.isEmpty) return 0;
    // Its listener moves each finished file into Music.
    await Downloads.instance.init();
    if (Platform.isAndroid) {
      await FileDownloader().permissions.request(PermissionType.notifications);
      // Needed only before Android 10; later ones let an app add to Music without asking.
      await FileDownloader().permissions.request(PermissionType.androidSharedStorage);
    }
    // One notification for all of them, counting files: one per track ran in parallel and
    // some stayed stuck at a percentage after their file was down.
    FileDownloader().configureNotificationForGroup(
      group,
      running: const TaskNotification('Saving to Music', '{numFinished} of {numTotal}'),
      complete: const TaskNotification('Saved to Music', '{numTotal} in Music/Homeplay'),
      error: const TaskNotification('Not all saved', '{numFailed} of {numTotal} failed'),
      progressBar: true,
      groupNotificationId: group,
    );
    var queued = 0;
    for (final t in audio) {
      final ok = await FileDownloader().enqueue(DownloadTask(
        taskId: 'phone_${t.id}_${DateTime.now().millisecondsSinceEpoch}',
        url: client.originalFileUrl(t).toString(),
        headers: client.headers,
        baseDirectory: BaseDirectory.temporary,
        directory: 'to_phone',
        filename: phoneFileName(t),
        displayName: t.name,
        group: group,
        // Where in Music it goes, read back when the file is down.
        metaData: phoneFolder(t),
        updates: Updates.status,
        retries: 3,
        priority: 0,
      ));
      if (ok) queued++;
    }
    return queued;
  }

  /// A finished file moves from the app's temporary folder into Music.
  static Future<void> onUpdate(TaskUpdate update) async {
    if (update is! TaskStatusUpdate || update.status != TaskStatus.complete) return;
    final task = update.task;
    if (task is! DownloadTask) return;
    final path = await task.filePath();
    final moved = await FileDownloader().moveFileToSharedStorage(path, SharedStorage.audio, directory: task.metaData);
    if (moved == null) {
      debugPrint('homeplay save to phone: could not move ${task.filename} into Music');
      final left = File(path);
      if (await left.exists()) await left.delete();
    }
  }
}

/// A name safe in any folder: no separators or characters Android's file systems refuse.
String _safe(String s, String fallback) {
  final clean = s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim().replaceAll(RegExp(r'^\.+'), '');
  return clean.isEmpty ? fallback : (clean.length > 100 ? clean.substring(0, 100).trim() : clean);
}

/// The file's own name on the server ("01-Cluster One.mp3"); without one, the track number and
/// title with the server's container as the extension.
String phoneFileName(JellyfinItem t) {
  final own = t.fileName;
  if (own != null && own.contains('.')) return _safe(own, 'track');
  final n = t.trackNumber;
  final name = '${n == null ? '' : '${n.toString().padLeft(2, '0')} '}${t.name}';
  return '${_safe(name, 'track')}.${t.container ?? 'mp3'}';
}

/// Homeplay/artist/album inside Music; tracks without an album go straight under the artist.
String phoneFolder(JellyfinItem t) =>
    ['Homeplay', _safe(artistOf(t), 'Unknown artist'), if (t.album != null) _safe(t.album!, 'Unknown album')].join('/');
