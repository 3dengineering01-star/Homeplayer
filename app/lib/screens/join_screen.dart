import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../services/account_store.dart';
import '../services/invite_link.dart';
import 'accounts_screen.dart';

/// A friend's invite: one button adds their server, with a sign-in made for this phone.
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
    final nav = Navigator.of(context);
    try {
      final account = await JellyfinClient.join(
        server: widget.invite.server,
        code: widget.invite.code,
        deviceId: await AccountStore.deviceId(),
        deviceName: await _deviceName(),
      );
      await AccountStore.add(account);
      await AccountStore.setLastOpened(account.id);
      // The server list opens the server used last: now this one.
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AccountsScreen()), (_) => false);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
}
