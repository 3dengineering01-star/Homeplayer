import 'package:flutter/material.dart';

import '../api/common.dart';
import '../api/discovery.dart';
import '../api/jellyfin.dart';
import '../api/subsonic.dart';
import '../models/account.dart';
import '../services/account_store.dart';

class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  ServerKind _kind = ServerKind.jellyfin;
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  List<DiscoveredServer> _found = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  Future<void> _discover() async {
    setState(() => _searching = true);
    final found = await discoverJellyfin();
    if (!mounted) return;
    setState(() {
      _found = found;
      _searching = false;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final baseUrl = normalizeBaseUrl(_url.text);
      final account = switch (_kind) {
        ServerKind.jellyfin => await JellyfinClient.login(
            baseUrl: baseUrl,
            username: _user.text.trim(),
            password: _pass.text,
            deviceId: await AccountStore.deviceId(),
          ),
        ServerKind.subsonic => await SubsonicClient.login(
            baseUrl: baseUrl,
            username: _user.text.trim(),
            password: _pass.text,
          ),
      };
      await AccountStore.add(account);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _discoveryRow(BuildContext context) {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Looking for Jellyfin on your network…'),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final s in _found)
          ActionChip(
            avatar: const Icon(Icons.dns, size: 18),
            label: Text('${s.name} · ${Uri.tryParse(s.address)?.authority ?? s.address}'),
            onPressed: () => setState(() => _url.text = s.address),
          ),
        TextButton.icon(
          onPressed: _discover,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(_found.isEmpty ? 'No server found on this network. Search again' : 'Search again'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final port = _kind == ServerKind.jellyfin ? 8096 : 4533;
    return Scaffold(
      appBar: AppBar(title: const Text('Add server')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ServerKind>(
            segments: const [
              ButtonSegment(value: ServerKind.jellyfin, label: Text('Jellyfin'), icon: Icon(Icons.video_library)),
              ButtonSegment(value: ServerKind.subsonic, label: Text('Navidrome / Subsonic'), icon: Icon(Icons.library_music)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          if (_kind == ServerKind.jellyfin) _discoveryRow(context),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Server address',
              helperText: 'For example 192.168.1.10:$port.\nAway from home: the Tailscale address, 100.x.y.z:$port',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _busy ? null : _connect(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _connect,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Connect'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
