import 'dart:async';

import 'package:flutter/material.dart';

import '../services/playback.dart';
import '../widgets/music_view.dart';
import '../widgets/video_view.dart';

/// Full-screen view of [Playback]. Leaving it stops a video; music keeps playing.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final Playback _pb = Playback.instance;

  @override
  void initState() {
    super.initState();
    // Not in the middle of building and disposing: the mini player sits in the same tree, and a
    // rebuild asked for while the tree is locked was lost in release builds (no mini player on
    // the screen under the player after going back).
    scheduleMicrotask(_pb.screenOpened);
  }

  @override
  void dispose() {
    scheduleMicrotask(_pb.screenClosed);
    if (_pb.currentItem?.isVideo ?? false) unawaited(_pb.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The queue too: a stop on the first track leaves the index at 0 but empties it.
    return ListenableBuilder(
      listenable: Listenable.merge([_pb.items, _pb.current, _pb.repeat]),
      builder: (context, _) {
        final index = _pb.current.value;
        final item = _pb.currentItem;
        if (item == null) {
          // Stopped from the notification while this screen was open: go back to the list.
          // Not when this screen is already on its way out (back from a video stops it during
          // the closing animation): then the pop would close the list under it too.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.of(context).maybePop();
          });
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Nothing is playing')));
        }
        final count = _pb.items.value.length;
        if (item.isVideo) {
          return VideoView(pb: _pb, item: item, hasPrev: index > 0, hasNext: index < count - 1);
        }
        return MusicView(pb: _pb, item: item, index: index, count: count);
      },
    );
  }
}
