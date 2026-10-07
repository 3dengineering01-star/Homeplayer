import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/jellyfin.dart';
import '../api/subsonic.dart';
import '../models/account.dart';
import '../services/account_store.dart';
import '../services/server_status.dart';
import '../widgets/appearance_picker.dart';
import '../widgets/library_tiles.dart';
import '../widgets/pressable.dart';
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
  String? _lastId;

  /// Whether each server answers; null while asking.
  final Map<String, bool?> _online = {};

  /// The app starts on the server opened last time; this list stays behind it, one step back.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await AccountStore.load();
    if (!_started) {
      _started = true;
      final last = await AccountStore.lastOpened();
      final open = pickStartAccount(accounts, last);
      // Opened before the list shows, so the list does not flash by on start.
      if (open != null) await _open(open, instant: true);
    }
    final last = await AccountStore.lastOpened();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _lastId = last;
    });
    _checkAll(accounts);
  }

  Future<void> _add() async {
    final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddAccountScreen()));
    if (added == true) _load();
  }

  Future<void> _open(Account a, {bool instant = false}) async {
    AccountStore.setLastOpened(a.id);
    _lastId = a.id;
    final Widget screen;
    switch (a.kind) {
      case ServerKind.jellyfin:
        screen = JellyfinHome(client: JellyfinClient(a, await AccountStore.deviceId()), title: a.serverName);
      case ServerKind.subsonic:
        screen = SubsonicArtists(client: SubsonicClient(a), title: a.serverName);
    }
    if (!mounted) return;
    Navigator.push(context, instant ? _InstantRoute(builder: (_) => screen) : MaterialPageRoute(builder: (_) => screen));
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
    final theme = Theme.of(context);
    void push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      body: accounts == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              SliverAppBar.large(
                title: const Text('Homeplay'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: () => push(const SettingsScreen()),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      accounts.isEmpty ? 'Your home media, everywhere' : '${greeting(DateTime.now())}. Where to?',
                      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ActionChip(
                        avatar: const Icon(Icons.download_for_offline_outlined),
                        label: const Text('Downloads'),
                        onPressed: () => push(const DownloadsScreen()),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.palette_outlined),
                        label: const Text('Appearance'),
                        onPressed: () => showAppearanceSheet(context),
                      ),
                    ]),
                  ]),
                ),
              ),
              if (accounts.isEmpty)
                SliverToBoxAdapter(child: _Welcome(onAdd: _add))
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.list(children: [
                    for (final (i, a) in accounts.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _ServerCard(
                          account: a,
                          index: i,
                          online: _online[a.id],
                          last: a.id == _lastId && accounts.length > 1,
                          onOpen: () {
                            HapticFeedback.selectionClick();
                            _open(a);
                          },
                          onBackup: a.kind == ServerKind.jellyfin ? () => push(BackupScreen(account: a)) : null,
                          onRemove: () => _remove(a),
                        ),
                      ),
                    _AddCard(onTap: _add),
                  ]),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ]),
    );
  }

  /// Asks every server whether it answers, for the dot on its card.
  void _checkAll(List<Account> accounts) {
    for (final a in accounts) {
      _online[a.id] = null;
      serverAnswers(a).then((up) {
        if (mounted) setState(() => _online[a.id] = up);
      });
    }
  }
}

/// A server as a big card in its own colour: what it is, whose it is, whether it answers.
class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.account,
    required this.index,
    required this.online,
    required this.last,
    required this.onOpen,
    required this.onBackup,
    required this.onRemove,
  });

  final Account account;
  final int index;

  /// Null while asking.
  final bool? online;

  /// Opened last time.
  final bool last;
  final VoidCallback onOpen;
  final VoidCallback? onBackup;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = libraryColors(context, index);
    final jellyfin = account.kind == ServerKind.jellyfin;
    final icon = jellyfin ? Icons.video_library_rounded : Icons.library_music_rounded;
    final host = Uri.tryParse(account.baseUrl)?.host ?? account.baseUrl;
    final (dot, status) = switch (online) {
      null => (fg.withValues(alpha: 0.4), 'Checking…'),
      true => (const Color(0xFF2EB872), 'Online'),
      false => (const Color(0xFFE5484D), 'Not reachable'),
    };
    return Pressable(
      child: Material(
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        color: bg,
        elevation: 0,
        child: InkWell(
          onTap: onOpen,
          onLongPress: () => _menu(context),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bg, Color.lerp(bg, fg, 0.14)!],
              ),
            ),
            child: Stack(children: [
              // A large faint copy of the icon in the corner.
              Positioned(right: -20, bottom: -28, child: Icon(icon, size: 150, color: fg.withValues(alpha: 0.08))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: fg.withValues(alpha: 0.12)),
                      child: Icon(icon, color: fg, size: 30),
                    ),
                    const Spacer(),
                    if (last)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: fg.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text('Last opened', style: theme.textTheme.labelSmall?.copyWith(color: fg)),
                      ),
                    IconButton(
                      tooltip: 'More',
                      icon: Icon(Icons.more_vert, color: fg),
                      onPressed: () => _menu(context),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Text(account.serverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${jellyfin ? 'Jellyfin' : 'Navidrome'} · ${account.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.85))),
                  const SizedBox(height: 12),
                  Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('$status · $host',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.8))),
                    ),
                    // Room for the arrow in the corner.
                    const SizedBox(width: 56),
                  ]),
                ]),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: fg,
                  child: Icon(Icons.arrow_forward_rounded, color: bg),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _menu(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(title: Text(account.serverName, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(account.baseUrl)),
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Open'),
              onTap: () {
                Navigator.pop(sheet);
                onOpen();
              },
            ),
            if (onBackup != null)
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Photo backup'),
                onTap: () {
                  Navigator.pop(sheet);
                  onBackup!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove server'),
              onTap: () {
                Navigator.pop(sheet);
                onRemove();
              },
            ),
          ]),
        ),
      );
}

/// The card at the end of the list that adds a server.
class _AddCard extends StatelessWidget {
  const _AddCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.add_rounded, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Add a server', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text('Jellyfin or Navidrome', style: theme.textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// No server yet: a friendly start.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primaryContainer, scheme.tertiaryContainer],
            ),
          ),
          child: Icon(Icons.home_rounded, size: 72, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 24),
        Text('Movies, shows and music from your own server',
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Add your Jellyfin or Navidrome server to start.',
            textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add your server')),
      ]),
    );
  }
}

/// The server to open on start: the one opened last, or the only one there is.
Account? pickStartAccount(List<Account> accounts, String? lastId) =>
    accounts.where((a) => a.id == lastId).firstOrNull ?? (accounts.length == 1 ? accounts.first : null);

/// Shows the page at once, without sliding in, and slides it out as usual on Back.
class _InstantRoute<T> extends MaterialPageRoute<T> {
  _InstantRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);
}
