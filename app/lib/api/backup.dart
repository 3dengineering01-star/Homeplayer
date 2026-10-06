import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'common.dart';
import 'jellyfin.dart';

const _timeout = Duration(seconds: 15);

/// A chunk can take a while on mobile data: 8 MB at 1 Mbit/s is about a minute.
const _chunkTimeout = Duration(minutes: 3);

/// Where an upload stands on the server: finished, or how many bytes it already has.
class UploadState {
  const UploadState({required this.done, required this.offset});

  /// The Jellyfin API writes PascalCase; lower case is accepted too.
  factory UploadState.fromJson(Map<String, dynamic> j) => UploadState(
        done: (j['Done'] ?? j['done']) as bool? ?? false,
        offset: ((j['Offset'] ?? j['offset']) as num?)?.toInt() ?? 0,
      );

  final bool done;
  final int offset;
}

enum BackupServerStatus {
  /// The Homeplay Backup plugin is not installed on the server.
  missing,

  /// Installed, but the admin has not chosen a folder yet.
  notConfigured,
  ready,
}

/// The Homeplay Backup plugin's API on a Jellyfin server (see server/README.md).
class BackupApi {
  BackupApi(this._jellyfin, {http.Client? client}) : _http = client ?? http.Client();

  final JellyfinClient _jellyfin;
  final http.Client _http;

  /// Below the plugin's 64 MB request limit, and small enough to lose little on a dropped connection.
  static const chunkSize = 8 * 1024 * 1024;

  String get _base => _jellyfin.account.baseUrl;

  void _checkAuth(http.Response res) {
    if (res.statusCode == 401) throw ApiException('Session expired. Remove the server and sign in again.');
  }

  Future<BackupServerStatus> status() async {
    final res = await _http.get(Uri.parse('$_base/HomeplayBackup/Info'), headers: _jellyfin.headers).timeout(_timeout);
    if (res.statusCode == 404) return BackupServerStatus.missing;
    _checkAuth(res);
    if (res.statusCode != 200) throw ApiException('Server answered ${res.statusCode} for backup info');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['Configured'] ?? j['configured']) as bool? ?? false)
        ? BackupServerStatus.ready
        : BackupServerStatus.notConfigured;
  }

  /// What the server already has of [ids]: finished files and partial uploads.
  Future<Map<String, UploadState>> check(String device, List<String> ids) async {
    final res = await _http
        .post(
          Uri.parse('$_base/HomeplayBackup/Check'),
          headers: {..._jellyfin.headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'Device': device, 'Ids': ids}),
        )
        .timeout(_timeout);
    _checkAuth(res);
    if (res.statusCode != 200) throw ApiException('Server answered ${res.statusCode} for backup check');
    return {
      for (final e in (jsonDecode(res.body) as List).cast<Map<String, dynamic>>())
        ((e['Id'] ?? e['id']) as String): UploadState.fromJson(e),
    };
  }

  /// Sends [file] in chunks from [offset], where the server's copy ends. [onProgress] gets the
  /// bytes the server has; [cancelled] is asked between chunks.
  Future<void> upload({
    required String device,
    required String id,
    required String name,
    required DateTime takenAt,
    required File file,
    int offset = 0,
    void Function(int sent, int size)? onProgress,
    bool Function()? cancelled,
  }) async {
    final size = await file.length();
    final raf = await file.open();
    try {
      var at = min(offset, size);
      var conflicts = 0;
      while (true) {
        if (cancelled?.call() ?? false) return;
        await raf.setPosition(at);
        final bytes = await raf.read(min(chunkSize, size - at));
        final uri = Uri.parse('$_base/HomeplayBackup/Upload').replace(queryParameters: {
          'device': device,
          'id': id,
          'name': name,
          'size': '$size',
          'takenAt': takenAt.toUtc().toIso8601String(),
          'offset': '$at',
        });
        final res = await _http
            .put(uri, headers: {..._jellyfin.headers, 'Content-Type': 'application/octet-stream'}, body: bytes)
            .timeout(_chunkTimeout);
        _checkAuth(res);
        if (res.statusCode == 507) throw ApiException('The server has no room for $name');
        if (res.statusCode != 200 && res.statusCode != 409) {
          throw ApiException('Server answered ${res.statusCode} while backing up $name');
        }
        final state = UploadState.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        onProgress?.call(state.done ? size : state.offset, size);
        if (state.done) return;
        // 409: the server has a different amount than we thought, e.g. after a lost answer.
        // Going on from its offset is right, but not forever.
        if (res.statusCode == 409 && ++conflicts > 3) throw ApiException('The server keeps refusing $name');
        if (res.statusCode == 200 && state.offset <= at) throw ApiException('The server took nothing of $name');
        at = state.offset;
      }
    } finally {
      await raf.close();
    }
  }
}

/// Short text for an error during backup.
String describeBackupError(Object e) {
  if (e is SocketException) return 'No connection to the server';
  // Android's answer when photo access was taken away in the system settings.
  if (e.toString().contains('SecurityException')) {
    return 'No access to photos. Open the backup settings in Homeplay to allow it.';
  }
  return describeError(e);
}
