import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../models/account.dart';
import '../services/account_store.dart';
import '../services/invite_link.dart';
import '../widgets/own_server_guide.dart';
import 'accounts_screen.dart';
import 'add_account_screen.dart';

/// A friend's invite: one button adds their server, with a sign-in made for this phone. Then it
/// opens the server, and shows how to make a server of one's own.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.invite});

  final InviteLink invite;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  String? _name;
  bool _busy = false;
  String? _error;

  /// The server once added.
  Account? _added;

  String get _host => Uri.tryParse(widget.invite.server)?.host ?? widget.invite.server;

  @override
  void initState() {
    super.initState();
    JellyfinClient.publicName(widget.invite.server).then((n) {
      if (mounted && n != null) setState(() => _name = n);
    });
  }

  Future<String> _deviceName() async {
    try {
      return (await DeviceInfoPlugin().androidInfo).model;
    } catch (_) {
      return 'Phone';
    }
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await JellyfinClient.join(
        server: widget.invite.server,
        code: widget.invite.code,
        deviceId: await AccountStore.deviceId(),
        deviceName: await _deviceName(),
      );
      await AccountStore.add(account);
      await AccountStore.setLastOpened(account.id);
      if (mounted) setState(() => _added = account);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The server list, which opens the server used last: the one just added.
  void _open() =>
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AccountsScreen()), (_) => false);

  Future<void> _addOwn() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AddAccountScreen()));
    if (added == true && mounted) _open();
  }

  @override
  Widget build(BuildContext context) {
    final added = _added;
    if (added != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _open();
        },
        child: _done(context, added),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Invite')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Center(
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.tertiaryContainer]),
              ),
              child: Icon(Icons.group_add_rounded, size: 56, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _name ?? _host,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'shares movies and music with you. Add it to watch and listen on this phone; '
            'you do not need a name or password.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(_host, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _busy ? null : _join,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add),
            label: const Text('Add to Homeplay'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }

  Widget _done(BuildContext context, Account added) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Invite')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.check_rounded, size: 48, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${added.serverName} is added',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'It is in your server list now. Watch and listen any time.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _open,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('Open ${added.serverName}'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 28),
          OwnServerGuide(servers: [added.baseUrl], onAdd: _addOwn),
        ],
      ),
    );
  }
}
