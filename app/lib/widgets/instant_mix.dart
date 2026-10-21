import 'package:flutter/material.dart';

import '../api/common.dart';
import '../services/playback.dart';
import '../services/track_lookup.dart';

/// Plays songs like [from] that its server picks ("Instant Mix"), after [seed] when the mix is
/// made from one song. If [seed] is the one playing, it goes on from where it is.
Future<void> playInstantMix(BuildContext context,
    {required String from, required Future<List<PlayItem>> Function() load, PlayItem? seed}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text('Making a mix from "$from"…')));
  final List<PlayItem> mix;
  try {
    mix = await load();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    return;
  }
  messenger.hideCurrentSnackBar();
  if (mix.isEmpty) {
    messenger.showSnackBar(const SnackBar(
        content: Text('The server found no similar songs. Navidrome needs Last.fm set up for this.')));
    return;
  }
  final pb = Playback.instance;
  final playingSeed = seed != null && identical(pb.currentItem, seed);
  await pb.start([?seed, ...mix], 0, startAt: playingSeed ? pb.player.state.position : null);
  messenger.showSnackBar(SnackBar(content: Text('Playing a mix of ${mix.length + (seed == null ? 0 : 1)} songs')));
}

/// The mix for a track known by its [PlayItem.ref]: the track first, then songs like it.
Future<void> playInstantMixOf(BuildContext context, PlayItem track) async {
  final ref = track.ref;
  if (ref == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('This track has no server to ask for similar songs')));
    return;
  }
  await playInstantMix(context, from: track.title, seed: track, load: () => TrackLookup.instantMix(ref));
}
