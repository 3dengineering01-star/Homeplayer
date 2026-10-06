import 'package:flutter/material.dart';

import '../api/jellyfin.dart';
import '../api/subsonic.dart';
import '../models/account.dart';
import '../services/account_store.dart';
import 'add_account_screen.dart';
import 'backup_screen.dart';
import 'downloads_screen.dart';
import 'jellyfin_home.dart';
import 'settings_screen.dart';
import 'subsonic_browser.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Account>? _accounts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await AccountStore.load();
    if (mounted) setState(() => _accounts = accounts);
  }

  Future<void> _add() async {
    final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddAccountScreen()));
    if (added == true) _load();
  }

  Future<void> _open(Account a) async {
    final Widget screen;
    switch (a.kind) {
      case ServerKind.jellyfin:
        screen = JellyfinHome(client: JellyfinClient(a, await AccountStore.deviceId()), title: a.serverName);
      case ServerKind.subsonic:
        screen = SubsonicArtists(client: SubsonicClient(a), title: a.serverName);
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _remove(Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove server?'),
        content: Text('${a.serverName}\n${a.username} @ ${a.baseUrl}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await AccountStore.remove(a.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      appBar: AppBar(title: const Text('Homeplay'), actions: [
        IconButton(
          icon: const Icon(Icons.download_for_offline_outlined),
          tooltip: 'Downloads',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen())),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add server'),
      ),
      body: accounts == null
          ? const Center(child: CircularProgressIndicator())
          : accounts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Add your Jellyfin or Navidrome server to start.', textAlign: TextAlign.center),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                  for (final a in accounts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: InkWell(
                          onTap: () => _open(a),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                                child: Icon(a.kind == ServerKind.jellyfin ? Icons.video_library : Icons.library_music),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(a.serverName,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${a.kind == ServerKind.jellyfin ? 'Jellyfin' : 'Navidrome'} · ${a.username}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ]),
                              ),
                              if (a.kind == ServerKind.jellyfin)
                                IconButton(
                                  icon: const Icon(Icons.backup_outlined),
                                  tooltip: 'Photo backup',
                                  onPressed: () => Navigator.push(
                                      context, MaterialPageRoute(builder: (_) => BackupScreen(account: a))),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Remove',
                                onPressed: () => _remove(a),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
    );
  }
}
