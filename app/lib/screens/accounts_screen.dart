import 'package:flutter/material.dart';

import '../api/jellyfin.dart';
import '../api/subsonic.dart';
import '../models/account.dart';
import '../services/account_store.dart';
import 'add_account_screen.dart';
import 'backup_screen.dart';
import 'jellyfin_browser.dart';
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
        screen = JellyfinBrowser(client: JellyfinClient(a, await AccountStore.deviceId()), title: a.serverName);
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
              : ListView(children: [
                  for (final a in accounts)
                    ListTile(
                      leading: Icon(a.kind == ServerKind.jellyfin ? Icons.video_library : Icons.library_music),
                      title: Text(a.serverName),
                      subtitle: Text('${a.username} · ${a.baseUrl}'),
                      onTap: () => _open(a),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
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
                ]),
    );
  }
}
