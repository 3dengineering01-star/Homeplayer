import 'dart:async';

import 'package:flutter/material.dart';

import '../models/account.dart';
import '../services/licence.dart';
import '../services/pro.dart';

/// Runs [open] when [feature] may be used here (with [account], or on any server when null);
/// otherwise shows what OwnMedia Pro is, and runs [open] once it is bought.
Future<void> withPro(BuildContext context, ProFeature feature, FutureOr<void> Function() open, {Account? account}) async {
  final ok = account != null ? await Pro.instance.mayUse(account) : await Pro.instance.mayUseAny();
  if (!context.mounted) return;
  if (!ok) {
    final bought = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProScreen(feature: feature)));
    if (bought != true || !context.mounted) return;
  }
  await open();
}

const _icons = {
  ProFeature.share: Icons.group_add_outlined,
  ProFeature.backup: Icons.backup_outlined,
  ProFeature.car: Icons.directions_car_outlined,
  ProFeature.tv: Icons.cast_outlined,
};

/// OwnMedia Pro: what it adds, how much of the free month is left, and the one purchase. Opened
/// from the settings, or instead of a [ProFeature] after the free month ([feature]); then it
/// closes with true once bought.
class ProScreen extends StatefulWidget {
  const ProScreen({super.key, this.feature, this.pro});

  final ProFeature? feature;

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

  // Bought while a feature waits: open it.
  void _changed() {
    if (widget.feature != null && _pro.status.value.bought && !_closing && mounted) {
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
          final feature = widget.feature;
          final title = s.bought
              ? 'OwnMedia Pro is yours'
              : s.trialLeft > 0
                  ? 'Pro free for ${s.trialLeft} more ${s.trialLeft == 1 ? 'day' : 'days'}'
                  : 'The free month of Pro is over';
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
              if (feature != null && !s.bought) ...[
                Text(
                  '${feature.title} is part of OwnMedia Pro. On a friend\'s server you can also ask its owner: '
                  'once they buy OwnMedia Pro, everyone they invited gets it too.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
              ],
              Text(
                s.bought
                    ? 'Thank you for supporting OwnMedia. Friends you invite to your server get Pro too.'
                    : 'Watching and listening stay free. OwnMedia Pro adds what goes beyond your phone: try it '
                        'free for $trialDays days, then buy once and keep it. No subscription.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
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
              const SizedBox(height: 16),
              // The buttons first, so they are in view on a small phone; what Pro adds below.
              for (final f in ProFeature.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_icons[f], color: scheme.primary),
                  title: Text(f.title),
                  subtitle: Text(f.what),
                ),
            ],
          );
        },
      ),
    );
  }
}
