import 'dart:async';

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
  /// What the server said last, with this screen's own changes on top: an invite made or taken
  /// back shows at once, without waiting for the server to be asked again.
  SharingInfo? _info;
  Object? _error;

  /// Invites being taken back: hidden already, brought back if the server refuses.
  final Set<String> _removing = {};

  /// Taken back and made on this screen: kept so, even if an answer from the server that left
  /// before the change still has the old list.
  final Set<String> _deleted = {};
  final Map<String, ShareInvite> _created = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Asks the server again. [quiet]: the list stays on screen meanwhile, and a failure only
  /// keeps it as it is.
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _error = null);
    try {
      var info = await _client.sharing();
      if (!mounted) return;
      for (final code in _deleted) {
        info = info.withoutInvite(code);
      }
      for (final invite in _created.values) {
        if (!info.invites.any((i) => i.code == invite.code)) info = info.withInvite(invite);
      }
      setState(() {
        _info = info;
        _error = null;
      });
    } catch (e) {
      debugPrint('homeplay sharing load failed: $e');
      if (mounted && (!quiet || _info == null)) setState(() => _error = e);
    }
  }

  JellyfinClient get _client => widget.client;

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _setAddress(String current) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddressDialog(client: _client, current: current),
    );
    if (saved != true || !mounted) return;
    await _load(quiet: true);
    // The address was all that was missing: on to the first invite.
    final info = _info;
    if (info != null && info.publicUrl.isNotEmpty && info.invites.isEmpty && mounted) await _invite(info);
  }

  Future<void> _invite(SharingInfo info) async {
    final created = await showModalBottomSheet<ShareInvite>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewInvite(client: _client, libraries: info.libraries),
    );
    if (created == null || !mounted) return;
    // In the list at once, then the link to send.
    setState(() {
      _created[created.code] = created;
      _info = _info?.withInvite(created);
    });
    unawaited(_load(quiet: true));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _LinkReady(invite: created, onSend: () => _send(created), onCopy: () => _copy(created)),
    );
  }

  Future<void> _send(ShareInvite invite) async {
    try {
      await AppLinks.share(inviteMessage(_client.account.serverName, invite.link), title: 'Send the invite');
    } catch (e) {
      // No share sheet: the link goes to the clipboard instead, to paste anywhere.
      debugPrint('homeplay share failed: $e');
      _copy(invite);
    }
  }

  void _copy(ShareInvite invite) {
    Clipboard.setData(ClipboardData(text: invite.link));
    _say('Link copied. Paste it in a message to ${invite.friend}.');
  }

  Future<void> _remove(ShareInvite invite) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(invite.state == InviteState.joined ? 'End ${invite.friend}\'s access?' : 'Take the invite back?'),
        content: Text(invite.state == InviteState.joined
            ? '${invite.device.isEmpty ? 'The phone that joined' : 'The ${invite.device} that joined'} by this invite '
                'will no longer see your server, at once. You can invite ${invite.friend} again later.'
            : 'The link will stop working.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Gone from the list at once; back if the server says no.
    setState(() => _removing.add(invite.code));
    try {
      await _client.deleteInvite(invite.code);
      if (!mounted) return;
      setState(() {
        _deleted.add(invite.code);
        _created.remove(invite.code);
        _info = _info?.withoutInvite(invite.code);
        _removing.remove(invite.code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _removing.remove(invite.code));
      _say(describeError(e));
    }
    unawaited(_load(quiet: true));
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('Share with friends')),
      body: Builder(
        builder: (context) {
          if (loaded == null && _error == null) return const Center(child: CircularProgressIndicator());
          if (loaded == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(describeError(_error!), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ]),
              ),
            );
          }
          final info = loaded.invites.any((i) => _removing.contains(i.code))
              ? loaded.invites.where((i) => _removing.contains(i.code)).fold(loaded, (a, i) => a.withoutInvite(i.code))
              : loaded;
          return RefreshIndicator(
            onRefresh: () => _load(quiet: true),
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
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        const Text(
                          'Nobody yet. Invite a friend: you get a link to send them. '
                          'It works once, and you can take it back any time.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _invite(info),
                          icon: const Icon(Icons.person_add),
                          label: const Text('Invite a friend'),
                        ),
                      ]),
                    ),
                  ...() {
                    Widget tile(ShareInvite i) => _InviteTile(
                          key: ValueKey(i.code),
                          invite: i,
                          onSend: () => _send(i),
                          onCopy: () => _copy(i),
                          onRemove: () => _remove(i),
                        );
                    final newest = info.invites.reversed;
                    final joined = [for (final i in newest) if (i.state == InviteState.joined) i];
                    final rest = [for (final i in newest) if (i.state != InviteState.joined) i];
                    return [
                      if (joined.isNotEmpty) ...[
                        _Heading('Who has access (${joined.length})'),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Text(
                            'A link works for whoever uses it first. If you do not know a phone here, '
                            'or someone you did not invite watches, end their access.',
                          ),
                        ),
                        for (final i in joined) tile(i),
                        const SizedBox(height: 16),
                      ],
                      if (rest.isNotEmpty) ...[
                        _Heading('Invites not used'),
                        for (final i in rest) tile(i),
                      ],
                    ];
                  }(),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: loaded == null || loaded.publicUrl.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _invite(loaded),
              icon: const Icon(Icons.person_add),
              label: const Text('Invite a friend'),
            ),
    );
  }
}

/// Right after an invite is made: the link itself, to send or copy at once.
class _LinkReady extends StatelessWidget {
  const _LinkReady({required this.invite, required this.onSend, required this.onCopy});

  final ShareInvite invite;
  final VoidCallback onSend;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('The link for ${invite.friend} is ready', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Send it in a message. It works once, for whoever opens it first.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(invite.link, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onSend();
            },
            icon: const Icon(Icons.send),
            label: const Text('Send the link'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onCopy();
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy the link'),
          ),
        ]),
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
            'OwnMediaSetup does it for you with the free Tailscale service, with no router settings:',
          ),
          const SizedBox(height: 12),
          step('1', 'On the computer with the server, run OwnMediaSetup again and keep "Let friends watch from anywhere" ticked.'),
          step('2', 'Sign in to Tailscale in the browser window that opens, and allow what it asks.'),
          step('3', 'Come back here and pull down to refresh: the address is already filled in.'),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: onSet,
            icon: const Icon(Icons.public),
            label: const Text('I have an address already'),
          ),
        ]),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({super.key, required this.invite, required this.onSend, required this.onCopy, required this.onRemove});

  final ShareInvite invite;
  final VoidCallback onSend;
  final VoidCallback onCopy;
  final VoidCallback onRemove;

  static String _date(DateTime d) => '${d.day}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final joined = invite.state == InviteState.joined;
    final lines = [
      invite.libraryNames.join(', '),
      switch (invite.state) {
        InviteState.waiting => 'Link not used yet · works until ${_date(invite.expires)}',
        InviteState.joined => ['Joined ${_date(invite.joined!)}', if (invite.device.isNotEmpty) 'from ${invite.device}'].join(' '),
        InviteState.expired => 'Link expired, not used',
      },
      if (joined)
        invite.watching != null
            ? 'Watching now: ${invite.watching}'
            : invite.lastSeen != null
                ? 'Last seen ${seenLabel(invite.lastSeen!, DateTime.now())}'
                : 'Not seen since joining',
    ];
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(joined ? (invite.watching != null ? Icons.play_arrow : Icons.person) : Icons.schedule_send),
        ),
        title: Text(invite.friend),
        subtitle: Text(lines.join('\n')),
        isThreeLine: true,
        trailing: joined
            ? IconButton(tooltip: 'End access', onPressed: onRemove, icon: const Icon(Icons.person_remove))
            : PopupMenuButton<VoidCallback>(
                tooltip: 'More',
                onSelected: (a) => a(),
                itemBuilder: (_) => [
                  if (invite.state == InviteState.waiting) ...[
                    PopupMenuItem(value: onSend, child: const ListTile(leading: Icon(Icons.send), title: Text('Send the link'))),
                    PopupMenuItem(value: onCopy, child: const ListTile(leading: Icon(Icons.copy), title: Text('Copy the link'))),
                  ],
                  PopupMenuItem(
                    value: onRemove,
                    child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Remove')),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
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
              'The link works once, for 7 days.\n'
              'Share only what you have the right to share: your own videos, photos and music, '
              'or what its owners allow you to share.',
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

/// The server's internet address: checked before it is kept, so a friend's link works. The
/// example under the field is only an example; an empty field is not saved.
class _AddressDialog extends StatefulWidget {
  const _AddressDialog({required this.client, required this.current});

  final JellyfinClient client;
  final String current;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  late final _field = TextEditingController(text: widget.current);
  bool _busy = false;
  String? _error;

  /// The address answered, but not as this server, or did not answer: saving is still allowed.
  String? _unchecked;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save({bool anyway = false}) async {
    final address = normalizeAddress(_field.text);
    if (address == null) {
      setState(() => _error = _field.text.trim().isEmpty
          ? 'Type the address Tailscale showed, like https://goodman.tail1234.ts.net'
          : 'That is not a web address. It looks like https://goodman.tail1234.ts.net');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      if (!anyway) {
        final (here, there) = await (
          JellyfinClient.publicId(widget.client.account.baseUrl),
          JellyfinClient.publicId(address),
        ).wait;
        if (there == null || (here != null && here != there)) {
          setState(() {
            _unchecked = address;
            _error = there == null
                ? 'Your server does not answer at this address. On the server computer, run OwnMediaSetup '
                      'again with "Let friends watch from anywhere" ticked. Then try again.'
                : 'This address leads to another server, not to this one.';
          });
          return;
        }
      }
      await widget.client.setPublicUrl(address);
      nav.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Internet address'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _field,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enabled: !_busy,
          onChanged: (_) => setState(() => _unchecked = null),
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            labelText: 'Address from Tailscale',
            helperText: 'For example https://goodman.tail1234.ts.net',
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const Row(children: [
            SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Expanded(child: Text('Checking that friends can reach your server…')),
          ]),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ]),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        if (_unchecked != null && _unchecked == normalizeAddress(_field.text))
          TextButton(onPressed: _busy ? null : () => _save(anyway: true), child: const Text('Save anyway')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
