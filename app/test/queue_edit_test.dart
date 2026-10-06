import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/queue_edit.dart';

void main() {
  const abcde = ['a', 'b', 'c', 'd', 'e'];

  test('moving an entry shifts the ones between', () {
    expect(moved(abcde, 1, 3), ['a', 'c', 'd', 'b', 'e']);
    expect(moved(abcde, 4, 0), ['e', 'a', 'b', 'c', 'd']);
    // Every entry's new index agrees with the moved list.
    for (final (from, to) in [(1, 3), (4, 0), (2, 2), (0, 4)]) {
      final after = moved(abcde, from, to);
      for (var i = 0; i < abcde.length; i++) {
        expect(after[indexAfterMove(i, from, to)], abcde[i], reason: 'move $from→$to, entry $i');
      }
    }
  });

  test('removing an entry shifts the later ones back', () {
    expect(indexAfterRemove(1, 3), 1);
    expect(indexAfterRemove(3, 3), isNull);
    expect(indexAfterRemove(4, 3), 3);
  });

  test("mpv's move target counts the entry still in place when moving down", () {
    expect(mpvMoveTarget(1, 3), 4);
    expect(mpvMoveTarget(3, 1), 1);
  });

  test('the moves between two orders rebuild the target', () {
    final random = Random(7);
    for (var n = 0; n < 50; n++) {
      final target = [...abcde]..shuffle(random);
      var work = [...abcde];
      for (final (from, to) in movesBetween(abcde, target)) {
        work = moved(work, from, to);
      }
      expect(work, target);
    }
    expect(movesBetween(abcde, abcde), isEmpty);
  });

  test('shuffle plays the chosen entry first and keeps every entry once', () {
    final order = shuffledOrder(10, 4, Random(1));
    expect(order.first, 4);
    expect(order.toSet(), {for (var i = 0; i < 10; i++) i});
    expect(order.length, 10);
  });

  test('unshuffle restores the original order, added entries last', () {
    expect(unshuffled(['c', 'x', 'a', 'b'], ['a', 'b', 'c']), ['a', 'b', 'c', 'x']);
    expect(unshuffled(['c', 'a'], ['a', 'b', 'c']), ['a', 'c']);
  });

  test('between tracks only when a finished track has another one after it', () {
    expect(betweenTracks(completed: true, index: 2, count: 5, repeats: false), isTrue);
    expect(betweenTracks(completed: true, index: 4, count: 5, repeats: false), isFalse, reason: 'the queue ended');
    expect(betweenTracks(completed: true, index: 4, count: 5, repeats: true), isTrue, reason: 'it starts over');
    expect(betweenTracks(completed: false, index: 2, count: 5, repeats: false), isFalse);
    expect(betweenTracks(completed: true, index: 0, count: 0, repeats: true), isFalse);
  });
}
