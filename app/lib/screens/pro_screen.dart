import 'dart:async';

import 'package:flutter/material.dart';

import '../services/licence.dart';
import '../services/pro.dart';

/// OwnMedia Pro: how much of the free month is left, and the one purchase. Opened from the
/// settings, or instead of a server when the free month is over ([server] is its name); then it
/// closes with true once bought.
class ProScreen extends StatefulWidget {
  const ProScreen({super.key, this.server, this.pro});

  final String? server;

  /// For tests; the app's own otherwise.
  final Pro? pro;

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  Pro get _pro => widget.pro ?? Pro.instance;
  StreamSubscription<String>? _messages;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _messages = _pro.messages.listen((text) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
    _pro.status.addListener(_changed);
  }

  @override
  void dispose() {
    _messages?.cancel();
    _pro.status.removeListener(_changed);
    super.dispose();
  }

  // Bought while a server waits: open it.
  void _changed() {
    if (widget.server != null && _pro.status.value.bought && !_closing && mounted) {
      _closing = true;
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('OwnMedia Pro')),
      body: ValueListenableBuilder<ProStatus>(
        valueListenable: _pro.status,
        builder: (context, s, _) {
          final server = widget.server;
          final title = s.bought
              ? 'OwnMedia Pro is yours'
              : s.trialLeft > 0
                  ? 'Free for ${s.trialLeft} more ${s.trialLeft == 1 ? 'day' : 'days'}'
                  : 'The free month is over';
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            children: [
              Center(
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.tertiaryContainer]),
                  ),
                  child: Icon(s.bought ? Icons.verified_rounded : Icons.workspace_premium_rounded,
                      size: 52, color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 24),
              Text(title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (server != null && !s.bought) ...[
                Text(
                  'To open $server, buy OwnMedia Pro. If $server is a friend\'s server, you can also ask them: '
                  'once its owner buys OwnMedia Pro, everyone they invited watches free.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
              ],
              Text(
                s.bought
                    ? 'Thank you for supporting OwnMedia. Friends you invite to your server watch free.'
                    : 'Try everything free for $trialDays days, then buy once and keep it: no subscription. '
                        'Friends you invite to your server watch free once you have bought it.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              if (!s.bought) ...[
                FilledButton.icon(
                  onPressed: s.price == null ? null : _pro.buy,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(s.price == null ? 'Google Play is not available' : 'Buy for ${s.price}'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _pro.restore, child: const Text('I bought it before: restore')),
              ],
            ],
          );
        },
      ),
    );
  }
}
