import '../api/common.dart';

/// The music queue as it is kept between runs of the app: the tracks by [TrackRef], the one
/// playing and where in it.
class SavedQueue {
  const SavedQueue(this.refs, this.index, this.position);

  final List<TrackRef> refs;
  final int index;
  final Duration position;

  Map<String, dynamic> toJson() =>
      {'refs': [for (final r in refs) r.toJson()], 'index': index, 'positionMs': position.inMilliseconds};

  /// Null for anything unreadable or empty.
  static SavedQueue? fromJson(Object? j) {
    if (j is! Map) return null;
    final refs = [for (final r in (j['refs'] as List?) ?? const []) ?TrackRef.fromJson(r)];
    final index = j['index'];
    if (refs.isEmpty || index is! int) return null;
    return SavedQueue(
      refs,
      index.clamp(0, refs.length - 1),
      Duration(milliseconds: (j['positionMs'] as num?)?.toInt() ?? 0),
    );
  }

  /// The queue to keep for [items] playing [current] at [position]: music only. Entries that
  /// cannot be found again are left out; null when the playing one is such an entry.
  static SavedQueue? of(List<PlayItem> items, int current, Duration position) {
    if (current < 0 || current >= items.length || items.any((i) => i.isVideo)) return null;
    if (items[current].ref == null) return null;
    final refs = <TrackRef>[];
    var index = 0;
    for (final (n, item) in items.indexed) {
      final ref = item.ref;
      if (ref == null) continue;
      if (n == current) index = refs.length;
      refs.add(ref);
    }
    return SavedQueue(refs, index, position);
  }

  /// The saved queue as found again: [found] has the tracks that still exist. The playing one
  /// stays playing if it is there (from where it was); otherwise the queue starts at the track
  /// that followed it. Null when nothing is left.
  ({List<PlayItem> items, int index, Duration position})? restore(Map<TrackRef, PlayItem> found) {
    final items = <PlayItem>[];
    int? index;
    var sameTrack = false;
    for (final (n, ref) in refs.indexed) {
      final item = found[ref];
      if (item == null) continue;
      if (n >= this.index && index == null) {
        index = items.length;
        sameTrack = n == this.index;
      }
      items.add(item);
    }
    if (items.isEmpty) return null;
    return (items: items, index: index ?? 0, position: sameTrack ? position : Duration.zero);
  }
}
