import 'package:flutter/material.dart';

import '../api/common.dart';

/// Loads a list, shows progress, errors with a retry button, and pull-to-refresh.
class AsyncList<T> extends StatefulWidget {
  const AsyncList({super.key, required this.load, required this.itemBuilder, this.emptyText = 'Nothing here'});

  final Future<List<T>> Function() load;
  final Widget Function(BuildContext context, List<T> items, int index) itemBuilder;
  final String emptyText;

  @override
  State<AsyncList<T>> createState() => _AsyncListState<T>();
}

class _AsyncListState<T> extends State<AsyncList<T>> {
  late Future<List<T>> _future = widget.load();

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _future = f);
    await f.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
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
        final items = snap.data!;
        return RefreshIndicator(
          onRefresh: _reload,
          child: items.isEmpty
              ? ListView(children: [
                  Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(widget.emptyText))),
                ])
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => widget.itemBuilder(context, items, i),
                ),
        );
      },
    );
  }
}

/// Square or poster thumbnail with a fallback icon.
class ArtThumb extends StatelessWidget {
  const ArtThumb({super.key, this.url, this.headers = const {}, required this.icon, this.aspect = 1});

  final Uri? url;
  final Map<String, String> headers;
  final IconData icon;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    const h = 56.0;
    final fallback = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(icon, size: 24),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: h,
        width: h * aspect,
        child: url == null
            ? fallback
            : Image.network(url.toString(),
                headers: headers, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}
