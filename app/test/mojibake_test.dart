import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/services/mojibake.dart';

/// [text] as a server shows it when its tag says Latin-1 but holds UTF-8.
String _utf8AsLatin1(String text) => String.fromCharCodes(utf8.encode(text));

void main() {
  test('Windows Cyrillic read as Latin-1 comes back', () {
    expect(fixMojibake('Êèíî'), 'Кино');
    expect(fixMojibake('Ãðóïïà êðîâè'), 'Группа крови');
    expect(fixMojibake('Ä Ä Ò - ×òî òàêîå îñåíü'), 'Д Д Т - Что такое осень');
    expect(fixMojibake('¨æèêè'), 'Ёжики');
  });

  test('UTF-8 read as Latin-1 comes back, in any script', () {
    expect(fixMojibake(_utf8AsLatin1('Кино')), 'Кино');
    expect(fixMojibake(_utf8AsLatin1('Ελληνικά')), 'Ελληνικά');
    expect(fixMojibake(_utf8AsLatin1('Zemfira — Хочешь?')), 'Zemfira — Хочешь?');
    // Through the Windows-1252 page instead: "—" is E2 80 94, and 0x80, 0x94 show as € and ”.
    expect(fixMojibake('â€”'), '—');
  });

  test('real names with accents stay as they are', () {
    for (final name in [
      'Mötley Crüe',
      'Sigur Rós',
      'Éléonore',
      'Björk',
      'Ærø',
      'Nóatún',
      'Glundroði (feat. Sigurboði Grétarsson)',
      'Heljarför (Vocal Version) [feat. Sigurboði Grétarsson]',
      'Françoise Hardy — Mon amie la rose',
      'Кино',
      'Beyoncé',
      'Ünïcödé',
      '',
      'Plain ASCII',
    ]) {
      expect(fixMojibake(name), name, reason: name);
    }
  });

  test('the item shows mended names everywhere', () {
    final item = JellyfinItem({
      'Id': 't',
      'Name': 'Ïåðåìåí',
      'Album': ' Ãðóïïà êðîâè ',
      'AlbumArtist': 'Êèíî',
      'Artists': ['Êèíî', 'Björk'],
    });
    expect(item.name, 'Перемен');
    expect(item.album, 'Группа крови');
    expect(item.albumArtist, 'Кино');
    expect(item.artists, ['Кино', 'Björk']);
  });
}
