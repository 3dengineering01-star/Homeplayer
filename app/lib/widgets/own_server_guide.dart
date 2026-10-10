import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_links.dart';
import '../services/own_server.dart';

/// How to make a Homeplay server of one's own, in three steps: the installer on the computer,
/// running it, adding the server on this phone. For someone who only has a friend's server.
class OwnServerGuide extends StatefulWidget {
  const OwnServerGuide({super.key, required this.servers, required this.onAdd, this.findLink = findSetupLink});

  /// The friends' servers this phone has: the installer comes from one of them.
  final List<String> servers;

  /// Opens adding a server, for the last step.
  final VoidCallback onAdd;

  final Future<String?> Function(List<String> servers) findLink;

  @override
  State<OwnServerGuide> createState() => _OwnServerGuideState();
}

class _OwnServerGuideState extends State<OwnServerGuide> {
  String? _link;
  bool _looking = true;

  @override
  void initState() {
    super.initState();
    widget.findLink(widget.servers).then((link) {
      if (mounted) {
        setState(() {
          _link = link;
          _looking = false;
        });
      }
    });
  }

  Future<void> _send() async {
    final link = _link!;
    try {
      await AppLinks.share(setupMessage(link), title: 'Send to your computer');
    } catch (_) {
      await _copy();
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _link!));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  Widget _download(ThemeData theme) {
    if (_looking) {
      return const Row(children: [
        SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Expanded(child: Text('Looking for the installer…')),
      ]);
    }
    if (_link == null) {
      return const Text('Ask whoever told you about Homeplay for the file HomeplaySetup.exe and copy it to your computer.');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Send yourself the link, for example in a messenger or by email. '
          'Open it on the computer: HomeplaySetup downloads.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(
          onPressed: _send,
          icon: const Icon(Icons.send_to_mobile_outlined),
          label: const Text('Send the link to my computer'),
        ),
        TextButton.icon(onPressed: _copy, icon: const Icon(Icons.copy, size: 18), label: const Text('Copy link')),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your own Homeplay', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Movies, music and photos from your own computer on this phone. '
            'Free, and nothing goes to the cloud. You need a computer with Windows.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _Step(number: 1, title: 'Get the installer on your computer', child: _download(theme)),
          const _Step(
            number: 2,
            title: 'Run HomeplaySetup on the computer',
            child: Text('Choose the folders with your movies, shows, music and photos, then your name and a password. '
                'It sets everything up by itself in a few minutes.'),
          ),
          _Step(
            number: 3,
            title: 'Add it on this phone',
            last: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Keep the phone on the same Wi-Fi as the computer. Tap Add your server: '
                  'Homeplay finds the computer by itself. Enter the name and password from step 2.'),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: widget.onAdd, icon: const Icon(Icons.add), label: const Text('Add your server')),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// One numbered step.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.child, this.last = false});

  final int number;
  final String title;
  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 8 : 20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: scheme.primaryContainer,
          child: Text('$number', style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            DefaultTextStyle.merge(style: theme.textTheme.bodyMedium, child: child),
          ]),
        ),
      ]),
    );
  }
}

/// The guide on a page of its own.
class OwnServerScreen extends StatelessWidget {
  const OwnServerScreen({super.key, required this.servers, required this.onAdd});

  final List<String> servers;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Your own server')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [OwnServerGuide(servers: servers, onAdd: onAdd)],
        ),
      );
}
