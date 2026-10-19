import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/services/saved_queue.dart';

PlayItem track(String id, {TrackSource source = TrackSource.jellyfin, bool video = false, bool ref = true}) => PlayItem(
      title: id,
      url: Uri.parse('http://server/$id'),
      isVideo: video,
      ref: ref ? TrackRef(source, id, accountId: 'acc') : null,
    );

void main() {
  test('refs survive JSON; unknown entries are dropped', () {
    const r = TrackRef(TrackSource.subsonic, 's1', accountId: 'a');
    expect(TrackRef.fromJson(r.toJson()), r);
    expect(TrackRef.fromJson({'source': 'spotify', 'id': 'x'}), isNull);
    expect(TrackRef.fromJson('nonsense'), isNull);
    final q = SavedQueue.fromJson({
      'refs': [r.toJson(), {'source': 'later', 'id': 'y'}],
      'index': 5,
      'positionMs': 1500,
    })!;
    expect(q.refs, [r]);
    expect(q.index, 0);
    expect(q.position, const Duration(milliseconds: 1500));
    expect(SavedQueue.fromJson({'refs': [], 'index': 0}), isNull);
  });

  test('only music is kept, and entries that cannot be found again are left out', () {
    final q = SavedQueue.of([track('a'), track('b', ref: false), track('c'), track('d')], 2, const Duration(seconds: 40))!;
    expect(q.refs.map((r) => r.id), ['a', 'c', 'd']);
    expect(q.index, 1);
    expect(SavedQueue.of([track('a'), track('v', video: true)], 0, Duration.zero), isNull);
    expect(SavedQueue.of([track('a', ref: false)], 0, Duration.zero), isNull);
    expect(SavedQueue.of(const [], 0, Duration.zero), isNull);
  });

  test('restored where it was, or from the next track when that one is gone', () {
    final items = [track('a'), track('b'), track('c')];
    final q = SavedQueue.of(items, 1, const Duration(seconds: 30))!;
    final all = {for (final i in items) i.ref!: i};
    final back = q.restore(all)!;
    expect(back.items.map((i) => i.title), ['a', 'b', 'c']);
    expect((back.index, back.position), (1, const Duration(seconds: 30)));

    final withoutB = q.restore({...all}..remove(items[1].ref))!;
    expect(withoutB.items.map((i) => i.title), ['a', 'c']);
    expect((withoutB.index, withoutB.position), (1, Duration.zero));

    final onlyA = q.restore({items[0].ref!: items[0]})!;
    expect((onlyA.index, onlyA.position), (0, Duration.zero));
    expect(q.restore(const {}), isNull);
  });
}
