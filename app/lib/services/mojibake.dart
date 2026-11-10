import 'dart:convert';

/// Names garbled by a wrong encoding, mended for display. Old MP3 tags often hold Cyrillic in
/// the Windows code page (or UTF-8) while saying they are Latin-1; the server reads them as
/// Latin-1 and "Кино" arrives as "Êèíî" (or "ÐšÐ¸Ð½Ð¾"). The bytes are all still there, so
/// reading them again the right way gives the name back.
///
/// Only text that cannot be a real name is changed: real Latin names with accents
/// ("Mötley Crüe", "Sigur Rós", "Éléonore") have few accented letters among plain ones.
String fixMojibake(String text) {
  // Nearly every name is plain ASCII: nothing to look at.
  if (!text.codeUnits.any((c) => c >= 0x80)) return text;
  final bytes = _asBytes(text);
  if (bytes == null) return text;
  // UTF-8 read as Latin-1: two or three accented signs per letter, and only valid UTF-8 decodes.
  if (bytes.any((b) => b >= 0x80)) {
    try {
      final utf = utf8.decode(bytes);
      if (utf != text && utf.runes.any((r) => r >= 0x100)) return utf;
    } on FormatException {
      // Not UTF-8; perhaps the Windows Cyrillic code page.
    }
  }
  // Windows-1251 read as Latin-1: Cyrillic letters land on À..ÿ (and Ё, ё on ¨, ¸).
  var high = 0, letters = 0;
  for (final b in bytes) {
    if (b >= 0xC0 || b == 0xA8 || b == 0xB8) {
      high++;
      letters++;
    } else if ((b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)) {
      letters++;
    }
  }
  if (high < 3 || high < letters * 0.6) return text;
  return String.fromCharCodes([for (final b in bytes) b < 0x80 ? b : _cp1251High.codeUnitAt(b - 0x80)]);
}

/// The text's characters as single bytes, when each is one: a Latin-1 character, or one of the
/// Windows-1252 signs in 0x80..0x9F (some servers read with that page instead). Null otherwise:
/// text with any other character was read right.
List<int>? _asBytes(String text) {
  final out = <int>[];
  for (final r in text.runes) {
    if (r < 0x100) {
      out.add(r);
    } else {
      final b = _cp1252Signs[r];
      if (b == null) return null;
      out.add(b);
    }
  }
  return out;
}

const _cp1252Signs = {
  0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87,
  0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91,
  0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98,
  0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
};

/// Windows-1251 from 0x80 to 0xFF.
const _cp1251High = 'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—\u0098™љ›њќћџ'
    ' ЎўЈ¤Ґ¦§Ё©Є«¬­®Ї°±Ііґµ¶·ё№є»јЅѕї'
    'АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'
    'абвгдежзийклмнопрстуфхцчшщъыьэюя';
