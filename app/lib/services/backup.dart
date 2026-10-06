import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/backup.dart';
import '../api/jellyfin.dart';
import '../models/account.dart';
import 'account_store.dart';
import 'backup_ledger.dart';

/// What a backup run is doing, for the backup screen.
class BackupProgress {
  const BackupProgress({required this.sent, this.current, this.fileSent = 0, this.fileSize = 0});

  /// Files finished in this run.
  final int sent;

  /// File name being sent, if any.
  final String? current;
  final int fileSent;
  final int fileSize;
}

/// Saved backup settings and the outcome of the last run.
class BackupSettings {
  const BackupSettings({this.accountId, this.since, this.lastRun, this.lastError});

  /// The Jellyfin account photos go to; null when backup is off.
  final String? accountId;

  /// Only photos taken from then on; null for all of them.
  final DateTime? since;
  final DateTime? lastRun;
  final String? lastError;

  bool get enabled => accountId != null;
}

/// Copies the phone's photos and videos to the Homeplay Backup plugin of a Jellyfin server:
/// every 15 minutes in the background (WorkManager), and on demand from the backup screen.
class Backup {
  static const _task = 'homeplay-backup';
  static const _accountKey = 'backup_account';
  static const _sinceKey = 'backup_since';
  static const _lastRunKey = 'backup_last_run';
  static const _lastErrorKey = 'backup_last_error';

  /// Photos and videos, with the place they were taken (otherwise Android strips GPS).
  static const permission = PermissionRequestOption(
    androidPermission: AndroidPermission(type: RequestType.common, mediaLocation: true),
  );

  static Future<void> init() => Workmanager().initialize(backupDispatcher);

  static Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    // The background run lives in another isolate with its own cache.
    await prefs.reload();
    return prefs;
  }

  static Future<BackupSettings> settings() async {
    final p = await _prefs();
    DateTime? time(String key) {
      final ms = p.getInt(key);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    return BackupSettings(
      accountId: p.getString(_accountKey),
      since: time(_sinceKey),
      lastRun: time(_lastRunKey),
      lastError: p.getString(_lastErrorKey),
    );
  }

  static Future<BackupLedger> ledger() async =>
      BackupLedger.open(File('${(await getApplicationSupportDirectory()).path}/backup_sent.txt'));

  /// Starts backing up to [account]: all photos, or only those taken from now on.
  static Future<void> enable(Account account, {required bool everything}) async {
    final p = await _prefs();
    // Another server knows nothing of what the old one got.
    if (p.getString(_accountKey) != account.id) await (await ledger()).clear();
    await p.setString(_accountKey, account.id);
    if (everything) {
      await p.remove(_sinceKey);
    } else {
      await p.setInt(_sinceKey, DateTime.now().millisecondsSinceEpoch);
    }
    await p.remove(_lastErrorKey);
    await Workmanager().registerPeriodicTask(
      _task,
      _task,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  static Future<void> disable() async {
    await Workmanager().cancelByUniqueName(_task);
    final p = await _prefs();
    await p.remove(_accountKey);
  }

  static Future<String> _device() async {
    try {
      return (await DeviceInfoPlugin().androidInfo).model;
    } catch (_) {
      return 'Phone';
    }
  }

  /// Sends what the server does not have yet, oldest first. Stops after [budget] (the system
  /// gives background work about 10 minutes) or when [cancelled] says so; the next run goes on
  /// from there, inside a file too. Returns the number of files sent.
  static Future<int> run({
    Duration? budget,
    void Function(BackupProgress)? onProgress,
    bool Function()? cancelled,
  }) async {
    final p = await _prefs();
    final accountId = p.getString(_accountKey);
    if (accountId == null) return 0;
    final deadline = budget == null ? null : DateTime.now().add(budget);
    bool stop() => (cancelled?.call() ?? false) || (deadline != null && DateTime.now().isAfter(deadline));
    var sent = 0;
    try {
      final account = (await AccountStore.load()).where((a) => a.id == accountId).firstOrNull;
      if (account == null) {
        await disable();
        return 0;
      }
      if (!(await PhotoManager.getPermissionState(requestOption: permission)).hasAccess) {
        throw const _BackupStop('No access to photos. Open the backup settings in Homeplay to allow it.');
      }
      final api = BackupApi(JellyfinClient(account, await AccountStore.deviceId()));
      switch (await api.status()) {
        case BackupServerStatus.missing:
          throw const _BackupStop('The Homeplay Backup plugin is not installed on the server.');
        case BackupServerStatus.notConfigured:
          throw const _BackupStop('The server has no backup folder yet. Set it in Jellyfin: Dashboard → Plugins → Homeplay Backup.');
        case BackupServerStatus.ready:
      }

      final device = await _device();
      final ledger = await Backup.ledger();
      final sinceMs = p.getInt(_sinceKey);
      final all = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.common,
        filterOption: FilterOptionGroup(
          createTimeCond: DateTimeCond(
            min: sinceMs == null ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.fromMillisecondsSinceEpoch(sinceMs),
            max: DateTime.now().add(const Duration(days: 1)),
          ),
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: true)],
        ),
      );
      if (all.isEmpty) return 0;
      const pageSize = 200;
      for (var page = 0; !stop(); page++) {
        final assets = await all.first.getAssetListPaged(page: page, size: pageSize);
        if (assets.isEmpty) break;
        final fresh = assets.where((a) => !ledger.contains(a.id)).toList();
        if (fresh.isEmpty) continue;
        final known = await api.check(device, [for (final a in fresh) a.id]);
        await ledger.addAll(fresh.where((a) => known[a.id]?.done ?? false).map((a) => a.id));
        for (final asset in fresh.where((a) => !(known[a.id]?.done ?? false))) {
          if (stop()) break;
          final file = await asset.originFile;
          if (file == null) {
            debugPrint('homeplay backup: no file for ${asset.id}');
            continue;
          }
          final name = await asset.titleAsync;
          onProgress?.call(BackupProgress(sent: sent, current: name));
          await api.upload(
            device: device,
            id: asset.id,
            name: name.isEmpty ? file.uri.pathSegments.last : name,
            takenAt: asset.createDateTime,
            file: file,
            offset: known[asset.id]?.offset ?? 0,
            cancelled: stop,
            onProgress: (done, size) =>
                onProgress?.call(BackupProgress(sent: sent, current: name, fileSent: done, fileSize: size)),
          );
          if (stop()) break; // the upload may have stopped part way
          await ledger.addAll([asset.id]);
          sent++;
          onProgress?.call(BackupProgress(sent: sent));
        }
      }
      await p.remove(_lastErrorKey);
    } on _BackupStop catch (e) {
      await p.setString(_lastErrorKey, e.message);
    } catch (e) {
      debugPrint('homeplay backup failed: $e');
      await p.setString(_lastErrorKey, describeBackupError(e));
    } finally {
      await p.setInt(_lastRunKey, DateTime.now().millisecondsSinceEpoch);
      // Android 10 copies originals into the cache before handing them out.
      await PhotoManager.clearFileCache();
    }
    return sent;
  }
}

class _BackupStop implements Exception {
  const _BackupStop(this.message);
  final String message;
}

/// Entry point of the background isolate WorkManager starts.
@pragma('vm:entry-point')
void backupDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Backup.run(budget: const Duration(minutes: 9));
    // Failures are saved for the backup screen; the periodic task stays scheduled anyway.
    return true;
  });
}
