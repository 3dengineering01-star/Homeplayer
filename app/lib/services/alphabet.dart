// The letters beside a long list sorted by name, to jump straight to one.

/// The letter [name] is filed under: its first letter in upper case, or '#' for a name that
/// starts with a digit or a sign.
String indexLetter(String name) {
  final first = name.trimLeft().runes.firstOrNull;
  if (first == null) return '#';
  final c = String.fromCharCode(first);
  return RegExp(r'\p{L}', unicode: true).hasMatch(c) ? c.toUpperCase() : '#';
}

/// Where each letter starts in [names], which are sorted by name: the letters in their order in
/// the list, each with the index of its first name.
List<({String letter, int index})> letterIndex(Iterable<String> names) {
  final seen = <String>{};
  return [
    for (final (i, name) in names.indexed)
      if (seen.add(indexLetter(name))) (letter: indexLetter(name), index: i),
  ];
}
