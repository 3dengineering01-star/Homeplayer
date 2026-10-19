import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/alphabet.dart';

void main() {
  test('a name is filed under its first letter, digits and signs under #', () {
    expect(indexLetter('abba'), 'A');
    expect(indexLetter('  Queen'), 'Q');
    expect(indexLetter('Ария'), 'А');
    expect(indexLetter('10cc'), '#');
    expect(indexLetter('!!!'), '#');
    expect(indexLetter(''), '#');
  });

  test('each letter points at its first name in the sorted list', () {
    final index = letterIndex(['10cc', 'abba', 'AC/DC', 'Beatles', 'Ария', 'Би-2']);
    expect([for (final e in index) '${e.letter}${e.index}'], ['#0', 'A1', 'B3', 'А4', 'Б5']);
  });
}
