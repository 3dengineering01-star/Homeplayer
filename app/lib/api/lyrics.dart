/// Song lyrics as the servers give them: lines with the moment they are sung, or plain text.
class LyricLine {
  const LyricLine(this.text, [this.start]);

  final String text;

  /// When the line is sung; null for lyrics without timing.
  final Duration? start;
}

class Lyrics {
  const Lyrics(this.lines, {this.source});

  final List<LyricLine> lines;

  /// Where they came from when not from the music server ("LRCLIB"), to say so under them.
  final String? source;

  /// The lines carry times: the player follows them and a tap jumps to one.
  bool get synced => lines.any((l) => l.start != null);
}

/// Null when there are no words, so callers have one "no lyrics" case.
Lyrics? _lyricsOrNull(List<LyricLine> lines) {
  // Blank lines at the ends say nothing; inside they are the pauses between verses.
  var first = 0, last = lines.length;
  while (first < last && lines[first].text.trim().isEmpty) {
    first++;
  }
  while (last > first && lines[last - 1].text.trim().isEmpty) {
    last--;
  }
  return first == last ? null : Lyrics(lines.sublist(first, last));
}

/// Jellyfin 10.9+ (/Audio/{id}/Lyrics): {Lyrics: [{Text, Start}]}, Start in 100 ns ticks.
Lyrics? lyricsFromJellyfin(Object? json) {
  if (json is! Map) return null;
  final raw = (json['Lyrics'] as List?) ?? const [];
  return _lyricsOrNull([
    for (final l in raw)
      if (l is Map)
        LyricLine(
          '${l['Text'] ?? ''}'.trimRight(),
          l['Start'] is num ? Duration(microseconds: (l['Start'] as num).toInt() ~/ 10) : null,
        ),
  ]);
}

/// OpenSubsonic getLyricsBySongId: the lyricsList object, with one entry per language or
/// version; the timed one wins. Start in milliseconds; a positive offset shows lines sooner.
Lyrics? lyricsFromOpenSubsonic(Object? lyricsList) {
  if (lyricsList is! Map) return null;
  final versions = [for (final v in (lyricsList['structuredLyrics'] as List?) ?? const []) if (v is Map) v];
  versions.sort((a, b) => (b['synced'] == true ? 1 : 0) - (a['synced'] == true ? 1 : 0));
  for (final v in versions) {
    final offset = (v['offset'] as num?)?.toInt() ?? 0;
    final synced = v['synced'] == true;
    final found = _lyricsOrNull([
      for (final l in (v['line'] as List?) ?? const [])
        if (l is Map)
          LyricLine(
            '${l['value'] ?? ''}'.trimRight(),
            synced && l['start'] is num
                ? Duration(milliseconds: ((l['start'] as num).toInt() - offset).clamp(0, 1 << 40))
                : null,
          ),
    ]);
    if (found != null) return found;
  }
  return null;
}

final _lrcTime = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _lrcTag = RegExp(r'^\[[a-zA-Z]+:.*\]$');
final _lrcOffset = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]$', caseSensitive: false);

/// Plain lyrics text, or the LRC format ("[01:02.50]words", a line may carry several times).
/// Subsonic's getLyrics gives either.
Lyrics? lyricsFromText(String? text) {
  if (text == null) return null;
  final rows = text.replaceAll('\r\n', '\n').split('\n');
  if (!rows.any((r) => _lrcTime.hasMatch(r))) {
    return _lyricsOrNull([for (final r in rows) LyricLine(r.trimRight())]);
  }
  var offset = 0;
  final timed = <LyricLine>[];
  for (final row in rows.map((r) => r.trim())) {
    final o = _lrcOffset.firstMatch(row);
    if (o != null) {
      offset = int.parse(o.group(1)!);
      continue;
    }
    if (_lrcTag.hasMatch(row) && !_lrcTime.hasMatch(row)) continue; // [ar:...], [ti:...]
    final times = _lrcTime.allMatches(row).toList();
    if (times.isEmpty) continue;
    final words = row.substring(times.last.end).trim();
    for (final t in times) {
      final fraction = t.group(3) ?? '0';
      final ms = int.parse(t.group(1)!) * 60000 +
          int.parse(t.group(2)!) * 1000 +
          (int.parse(fraction) * switch (fraction.length) { 1 => 100, 2 => 10, _ => 1 });
      timed.add(LyricLine(words, Duration(milliseconds: (ms - offset).clamp(0, 1 << 40))));
    }
  }
  timed.sort((a, b) => a.start!.compareTo(b.start!));
  return _lyricsOrNull(timed);
}

/// The line sung at [position]: the last one started by then, -1 before the first.
int currentLyricLine(List<LyricLine> lines, Duration position) {
  var low = 0, high = lines.length - 1, found = -1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    final start = lines[mid].start;
    if (start == null || start <= position) {
      found = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return found;
}
