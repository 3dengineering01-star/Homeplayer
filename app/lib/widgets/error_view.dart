import 'package:flutter/material.dart';

import '../api/common.dart';
import '../screens/downloads_screen.dart';
import '../services/connection.dart';

/// A page that could not be loaded: what went wrong and Retry. When the connection is the
/// trouble, also the way to what plays without it: Downloads.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: Connection.offline,
        builder: (context, offline, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(errorMessage(error, offline: offline), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                if (netProblem(error, offline: offline) != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: const Text('Downloads'),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadsScreen())),
                  ),
              ]),
            ]),
          ),
        ),
      );
}
