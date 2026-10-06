import 'dart:math';

/// A copy of [list] with the entry at [from] moved to [to] (its final position).
List<T> moved<T>(List<T> list, int from, int to) {
  final copy = [...list];
  copy.insert(to, copy.removeAt(from));
  return copy;
}

/// Where the entry at [i] ends up after the entry at [from] moves to [to].
int indexAfterMove(int i, int from, int to) {
  if (i == from) return to;
  if (from < to && i > from && i <= to) return i - 1;
  if (to < from && i >= to && i < from) return i + 1;
  return i;
}

/// Where the entry at [i] ends up after the entry at [removed] goes; null for that entry.
int? indexAfterRemove(int i, int removed) => i == removed ? null : (i > removed ? i - 1 : i);

/// mpv's playlist-move puts the entry before [to] of the list as it was: moving down needs one more.
int mpvMoveTarget(int from, int to) => to > from ? to + 1 : to;

/// The moves (from, to; final positions, applied one after another) that turn [current] into
/// [target]. Both hold the same entries.
List<(int, int)> movesBetween<T>(List<T> current, List<T> target) {
  final work = [...current];
  final moves = <(int, int)>[];
  for (var i = 0; i < target.length && i < work.length; i++) {
    final j = work.indexOf(target[i], i);
    if (j < 0 || j == i) continue;
    work.insert(i, work.removeAt(j));
    moves.add((j, i));
  }
  return moves;
}

/// Shuffled play order of [length] entries: [first] plays first, the rest in random order.
List<int> shuffledOrder(int length, int first, Random random) {
  final rest = [for (var i = 0; i < length; i++) if (i != first) i]..shuffle(random);
  return [first, ...rest];
}

/// [items] back in the order of [original]; entries added since keep their place at the end.
List<T> unshuffled<T>(List<T> items, List<T> original) {
  final rank = {for (final (i, e) in original.indexed) e: i};
  final known = items.where(rank.containsKey).toList()..sort((a, b) => rank[a]!.compareTo(rank[b]!));
  return [...known, ...items.where((e) => !rank.containsKey(e))];
}
