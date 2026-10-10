import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../api/sharing.dart';
import '../services/app_links.dart';
import '../services/invite_link.dart';

/// The owner shares the server: the address friends reach it at, the invites made, and a new
/// invite link for a friend with the libraries they may see.
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key, required this.client});

  final JellyfinClient client;

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  late Future<SharingInfo> _sharing = widget.client.sharing();

  void _reload() => setState(() => _sharing = widget.client.sharing());

  JellyfinClient get _client => widget.client;

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _setAddress(String current) async {
    final field = TextEditingController(text: current);
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Internet address'),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'https://your-pc.tail1234.ts.net'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, field.text), child: const Text('Save')),
        ],
      ),
    );
    field.dispose();
    if (text == null) return;
    try {
      await _client.setPublicUrl(text.trim());
      _reload();
    } catch (e) {
      if (mounted) _say(describeError(e));
    }
  }

  Future<void> _invite(SharingInfo info) async {
    final created = await showModalBottomSheet<ShareInvite>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewInvite(client: _client, libraries: info.libraries),
    );
    if (created == null || !mounted) return;
    _reload();
    await _send(created);
  }

  Future<void> _send(ShareInvite invite) =>
      AppLinks.share(inviteMessage(_client.account.serverName, invite.link), title: 'Send the invite');

  Future<void> _remove(ShareInvite invite) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(invite.state == InviteState.joined ? 'End ${invite.friend}\'s access?' : 'Take the invite back?'),
        content: Text(invite.state == InviteState.joined
            ? '${invite.friend} will no longer see your server. You can invite them again later.'
            : 'The link will stop working.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.deleteInvite(invite.code);
      _reload();
    } catch (e) {
      if (mounted) _say(describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share with friends')),
      body: FutureBuilder<SharingInfo>(
        future: _sharing,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(describeError(snap.error!), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                ]),
              ),
            );
          }
          final info = snap.data!;
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _sharing.then((_) {}, onError: (_) {});
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (info.publicUrl.isEmpty)
                  _InternetSetup(onSet: () => _setAddress(''))
                else ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.public),
                      title: const Text('Friends reach your server at'),
                      subtitle: Text(info.publicUrl),
                      trailing: TextButton(onPressed: () => _setAddress(info.publicUrl), child: const Text('Change')),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (info.invites.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nobody yet. Tap "Invite a friend": you get a link to send them. '
                        'It works once, and you can take it back any time.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final i in info.invites.reversed)
                    _InviteTile(
                      invite: i,
                      onSend: () => _send(i),
                      onCopy: () {
                        Clipboard.setData(ClipboardData(text: i.link));
                        _say('Link copied');
                      },
                      onRemove: () => _remove(i),
                    ),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FutureBuilder<SharingInfo>(
        future: _sharing,
        builder: (context, snap) => snap.data == null || snap.data!.publicUrl.isEmpty
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                onPressed: () => _invite(snap.data!),
                icon: const Icon(Icons.person_add),
                label: const Text('Invite a friend'),
              ),
      ),
    );
  }
}

/// Before the first invite: how to give the server an internet address.
class _InternetSetup extends StatelessWidget {
  const _InternetSetup({required this.onSet});

  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 12, child: Text(n, style: const TextStyle(fontSize: 13))),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('First: your server on the internet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Friends are not on your Wi-Fi, so they reach your server over the internet. '
            'The free Tailscale app gives it a safe address, with no router settings:',
          ),
          const SizedBox(height: 12),
          step('1', 'On the computer with the server, install Tailscale from tailscale.com/download and sign in.'),
          step('2', 'Open Command Prompt as administrator and run:\ntailscale funnel --bg 8096\nIt shows the address, like https://your-pc.tail1234.ts.net'),
          step('3', 'Enter that address here.'),
          const SizedBox(height: 4),
          FilledButton.icon(onPressed: onSet, icon: const Icon(Icons.public), label: const Text('Enter the address')),
        ]),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({required this.invite, required this.onSend, required this.onCopy, required this.onRemove});

  final ShareInvite invite;
  final VoidCallback onSend;
  final VoidCallback onCopy;
  final VoidCallback onRemove;

  static String _date(DateTime d) => '${d.day}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final state = switch (invite.state) {
      InviteState.waiting => 'Link not used yet · works until ${_date(invite.expires)}',
      InviteState.joined => 'Joined ${_date(invite.joined!)}',
      InviteState.expired => 'Link expired, not used',
    };
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(invite.state == InviteState.joined ? Icons.person : Icons.schedule_send),
        ),
        title: Text(invite.friend),
        subtitle: Text('${invite.libraryNames.join(', ')}\n$state'),
        isThreeLine: true,
        trailing: PopupMenuButton<VoidCallback>(
          tooltip: 'More',
          onSelected: (a) => a(),
          itemBuilder: (_) => [
            if (invite.state == InviteState.waiting) ...[
              PopupMenuItem(value: onSend, child: const ListTile(leading: Icon(Icons.send), title: Text('Send the link'))),
              PopupMenuItem(value: onCopy, child: const ListTile(leading: Icon(Icons.copy), title: Text('Copy the link'))),
            ],
            PopupMenuItem(
              value: onRemove,
              child: ListTile(
                leading: const Icon(Icons.person_remove),
                title: Text(invite.state == InviteState.joined ? 'End access' : 'Remove'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A new invite: the friend's name and the libraries they see (photos left out unless ticked).
class _NewInvite extends StatefulWidget {
  const _NewInvite({required this.client, required this.libraries});

  final JellyfinClient client;
  final List<ShareLibrary> libraries;

  @override
  State<_NewInvite> createState() => _NewInviteState();
}

class _NewInviteState extends State<_NewInvite> {
  final _name = TextEditingController();
  late final Set<String> _chosen = {for (final l in widget.libraries) if (l.sharedByDefault) l.id};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      final invite = await widget.client.createInvite(
        friend: _name.text.trim(),
        libraryIds: [for (final l in widget.libraries) if (_chosen.contains(l.id)) l.id],
      );
      nav.pop(invite);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Invite a friend', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: "Friend's name"),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text('They see:', style: theme.textTheme.titleSmall),
            for (final l in widget.libraries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _chosen.contains(l.id),
                title: Text(l.name),
                subtitle: l.sharedByDefault ? null : const Text('Personal: not shared unless you tick it'),
                onChanged: (on) => setState(() => on == true ? _chosen.add(l.id) : _chosen.remove(l.id)),
              ),
            Text(
              'They can watch and listen, and cannot delete anything or invite others. '
              'The link works once, for 7 days.',
              style: theme.textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || _chosen.isEmpty || _name.text.trim().isEmpty ? null : _create,
              icon: const Icon(Icons.link),
              label: const Text('Make the link'),
            ),
          ],
        ),
      ),
    );
  }
}
