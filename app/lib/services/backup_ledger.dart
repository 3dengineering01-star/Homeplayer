import 'dart:io';

/// Ids of photos already on the server, one per line, so a run only asks the server about new
/// ones. The server stays the authority: a lost ledger costs one check per photo, not a re-upload.
class BackupLedger {
  BackupLedger._(this._file, this._ids);

  final File _file;
  final Set<String> _ids;

  static Future<BackupLedger> open(File file) async {
    final ids = await file.exists() ? (await file.readAsLines()).where((l) => l.isNotEmpty).toSet() : <String>{};
    return BackupLedger._(file, ids);
  }

  int get length => _ids.length;

  bool contains(String id) => _ids.contains(id);

  /// Appends at once, so a run cut short by the system keeps what it sent.
  Future<void> addAll(Iterable<String> ids) async {
    final fresh = ids.where(_ids.add).toList();
    if (fresh.isEmpty) return;
    await _file.parent.create(recursive: true);
    await _file.writeAsString('${fresh.join('\n')}\n', mode: FileMode.append, flush: true);
  }

  Future<void> clear() async {
    _ids.clear();
    if (await _file.exists()) await _file.delete();
  }
}
