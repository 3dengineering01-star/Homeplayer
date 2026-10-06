import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../api/backup.dart';
import '../api/jellyfin.dart';
import '../models/account.dart';
import '../services/account_store.dart';
import '../services/backup.dart';

/// Backup of the phone's photos and videos to one Jellyfin server.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.account});

  final Account account;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupSettings? _settings;
  BackupServerStatus? _server;
  String? _serverError;
  int _onServer = 0;

  BackupProgress? _progress;
  bool _stopping = false;

  bool get _running => _progress != null;
  bool get _here => _settings?.accountId == widget.account.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await Backup.settings();
    final count = (await Backup.ledger()).length;
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _onServer = settings.accountId == widget.account.id ? count : 0;
    });
    try {
      final api = BackupApi(JellyfinClient(widget.account, await AccountStore.deviceId()));
      final status = await api.status();
      if (mounted) {
        setState(() {
          _server = status;
          _serverError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _serverError = describeBackupError(e));
    }
  }

  Future<void> _toggle(bool on) async {
    if (!on) {
      await Backup.disable();
      return _load();
    }
    final access = await PhotoManager.requestPermissionExtend(requestOption: Backup.permission);
    if (!access.hasAccess) {
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('No access to photos'),
          content: const Text('Homeplay needs access to your photos and videos to back them up.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open settings')),
          ],
        ),
      );
      if (open == true) await PhotoManager.openSetting();
      return;
    }
    if (!mounted) return;
    final everything = await showDialog<bool>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('What to back up?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, true),
            child: const ListTile(
              leading: Icon(Icons.photo_library_outlined),
              title: Text('All photos and videos'),
              subtitle: Text('Everything on the phone, then new ones as they appear'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, false),
            child: const ListTile(
              leading: Icon(Icons.new_releases_outlined),
              title: Text('Only new ones'),
              subtitle: Text('Taken from now on'),
            ),
          ),
        ],
      ),
    );
    if (everything == null) return;
    await Backup.enable(widget.account, everything: everything);
    await _load();
    _runNow();
  }

  Future<void> _runNow() async {
    setState(() {
      _progress = const BackupProgress(sent: 0);
      _stopping = false;
    });
    await Backup.run(
      cancelled: () => _stopping || !mounted,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() => _progress = null);
    await _load();
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${t.day}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  }

  Widget _serverCard(ThemeData theme) {
    final (icon, text) = switch ((_server, _serverError)) {
      (_, final String error) => (Icons.cloud_off, error),
      (null, _) => (Icons.hourglass_empty, 'Checking the server...'),
      (BackupServerStatus.missing, _) => (
          Icons.extension_off,
          'Install the Homeplay Backup plugin on this Jellyfin server to back up photos to it.'
        ),
      (BackupServerStatus.notConfigured, _) => (
          Icons.folder_off,
          'The plugin is installed, but has no folder yet. Set it in Jellyfin: Dashboard → Plugins → Homeplay Backup.'
        ),
      (BackupServerStatus.ready, _) => (Icons.cloud_done, 'The server is ready to take photos.'),
    };
    return ListTile(leading: Icon(icon, color: theme.colorScheme.primary), title: Text(text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;
    final ready = _server == BackupServerStatus.ready;
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('Photo backup')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              _serverCard(theme),
              SwitchListTile(
                title: const Text('Back up photos and videos'),
                subtitle: Text(_here
                    ? 'To ${widget.account.serverName}, by Wi-Fi or mobile data, every 15 minutes'
                    : settings.enabled
                        ? 'Now backing up to another server; turning this on moves it here'
                        : 'Copies go to ${widget.account.serverName}; nothing is deleted from the phone'),
                value: _here,
                onChanged: _running || (!ready && !_here) ? null : _toggle,
              ),
              if (_here) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text('$_onServer on the server'),
                  subtitle: Text(settings.since == null
                      ? 'All photos and videos'
                      : 'Taken since ${_ago(settings.since!)}'),
                ),
                ListTile(
                  leading: Icon(settings.lastError == null ? Icons.schedule : Icons.error_outline,
                      color: settings.lastError == null ? null : theme.colorScheme.error),
                  title: Text(settings.lastRun == null ? 'Not run yet' : 'Last run ${_ago(settings.lastRun!)}'),
                  subtitle: settings.lastError == null ? null : Text(settings.lastError!),
                ),
                if (progress != null)
                  ListTile(
                    leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                    title: Text(progress.current == null
                        ? 'Looking for new photos... ${progress.sent} sent'
                        : '${progress.current} · ${progress.sent} sent'),
                    subtitle: progress.fileSize > 0
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(value: progress.fileSent / progress.fileSize),
                          )
                        : null,
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _running
                      ? OutlinedButton.icon(
                          onPressed: _stopping ? null : () => setState(() => _stopping = true),
                          icon: const Icon(Icons.stop),
                          label: Text(_stopping ? 'Stopping...' : 'Stop'),
                        )
                      : FilledButton.icon(
                          onPressed: ready ? _runNow : null,
                          icon: const Icon(Icons.backup),
                          label: const Text('Back up now'),
                        ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Files go to the backup folder on the server, as user / phone / year / month. '
                  'Large videos continue where they stopped if the connection drops.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ]),
    );
  }
}
