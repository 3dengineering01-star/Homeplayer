/// What a Jellyfin server knows about a video beyond the file: where the intro and the credits
/// are (media segments, Jellyfin 10.10+, filled by a plugin such as Intro Skipper or from the
/// chapters) and the small pictures along the timeline for seeking (trickplay, Jellyfin 10.9+,
/// made when the library has it turned on). Pure rules here; the requests are in jellyfin.dart.
library;

/// A kind of part the viewer may want to skip.
enum SegmentKind {
  intro('Skip intro'),
  recap('Skip recap'),
  outro('Skip credits'),
  preview('Skip preview'),
  commercial('Skip ad');

  const SegmentKind(this.label);

  /// The button's text.
  final String label;

  /// The kind for Jellyfin's segment type; null for those not worth a button ("Unknown").
  static SegmentKind? fromServer(Object? type) => switch (type) {
        'Intro' => intro,
        'Recap' => recap,
        'Outro' => outro,
        'Preview' => preview,
        'Commercial' => commercial,
        _ => null,
      };
}

/// One part of a video, from [start] to [end].
class MediaSegment {
  const MediaSegment(this.kind, this.start, this.end);

  final SegmentKind kind;
  final Duration start;
  final Duration end;

  @override
  bool operator ==(Object other) => other is MediaSegment && other.kind == kind && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => 'MediaSegment(${kind.name}, $start, $end)';
}

/// Shorter parts get no button: by the time it shows, they are over.
const minSkippable = Duration(seconds: 3);

/// The segments in a /MediaSegments answer, in time order; nothing for an answer of another shape.
List<MediaSegment> parseSegments(Object? json) {
  final items = json is Map ? json['Items'] : null;
  if (items is! List) return const [];
  final out = <MediaSegment>[];
  for (final s in items) {
    if (s is! Map) continue;
    final kind = SegmentKind.fromServer(s['Type']);
    final start = s['StartTicks'], end = s['EndTicks'];
    if (kind == null || start is! num || end is! num) continue;
    final from = Duration(microseconds: start.toInt() ~/ 10), to = Duration(microseconds: end.toInt() ~/ 10);
    if (to - from < minSkippable || from.isNegative) continue;
    out.add(MediaSegment(kind, from, to));
  }
  return out..sort((a, b) => a.start.compareTo(b.start));
}

/// The segment playing at [position] that a button may skip: from its start until a second
/// before its end, when skipping would no longer gain anything.
MediaSegment? skippableAt(List<MediaSegment> segments, Duration position) {
  for (final s in segments) {
    if (position >= s.start && position < s.end - const Duration(seconds: 1)) return s;
  }
  return null;
}

/// Whether skipping [s] means going to the next video: credits that run to the end of the file
/// (a few seconds of slack, servers round the end).
bool endsVideo(MediaSegment s, Duration? duration) =>
    s.kind == SegmentKind.outro && duration != null && duration > Duration.zero && s.end >= duration - const Duration(seconds: 5);

/// The pictures along a video's timeline: [count] pictures of [width]×[height], one every
/// [interval], laid out in sheets of [columns]×[rows], row by row. Every sheet has the full size,
/// the last one too: Jellyfin leaves the places after the last picture black.
class Trickplay {
  const Trickplay({
    required this.width,
    required this.height,
    required this.columns,
    required this.rows,
    required this.count,
    required this.interval,
  });

  final int width;
  final int height;
  final int columns;
  final int rows;
  final int count;
  final Duration interval;

  int get _perSheet => columns * rows;

  /// Where the picture for [position] is: which sheet, and its column and row there.
  ({int sheet, int column, int row}) tileAt(Duration position) {
    final ms = interval.inMilliseconds;
    final index = (ms <= 0 ? 0 : position.inMilliseconds ~/ ms).clamp(0, count - 1);
    final inSheet = index % _perSheet;
    return (sheet: index ~/ _perSheet, column: inSheet % columns, row: inSheet ~/ columns);
  }

  @override
  bool operator ==(Object other) =>
      other is Trickplay &&
      other.width == width &&
      other.height == height &&
      other.columns == columns &&
      other.rows == rows &&
      other.count == count &&
      other.interval == interval;

  @override
  int get hashCode => Object.hash(width, height, columns, rows, count, interval);
}

/// The size of picture the app asks for: the server's closest at or above this width, else its
/// largest. Small enough to load quickly over mobile data, sharp enough at the size it is shown.
const trickplayWidth = 320;

/// The pictures for [mediaSourceId] (or the item's only file, when null) in the Trickplay field of
/// an item; null when the server made none.
Trickplay? parseTrickplay(Object? field, String? mediaSourceId) {
  if (field is! Map || field.isEmpty) return null;
  final bySize = field[mediaSourceId] ?? (field.length == 1 ? field.values.first : null);
  if (bySize is! Map) return null;
  final sizes = <Trickplay>[];
  for (final t in bySize.values) {
    if (t is! Map) continue;
    final w = t['Width'], h = t['Height'], c = t['TileWidth'], r = t['TileHeight'], n = t['ThumbnailCount'], i = t['Interval'];
    if (w is! num || h is! num || c is! num || r is! num || n is! num || i is! num) continue;
    if (w <= 0 || h <= 0 || c <= 0 || r <= 0 || n <= 0 || i <= 0) continue;
    sizes.add(Trickplay(
      width: w.toInt(),
      height: h.toInt(),
      columns: c.toInt(),
      rows: r.toInt(),
      count: n.toInt(),
      interval: Duration(milliseconds: i.toInt()),
    ));
  }
  if (sizes.isEmpty) return null;
  sizes.sort((a, b) => a.width.compareTo(b.width));
  return sizes.where((t) => t.width >= trickplayWidth).firstOrNull ?? sizes.last;
}

/// Everything above for one video; [sheetUrl] gives the address of a sheet of pictures.
class VideoExtras {
  const VideoExtras({this.segments = const [], this.trickplay, this.sheetUrl});

  final List<MediaSegment> segments;
  final Trickplay? trickplay;
  final Uri Function(int sheet)? sheetUrl;

  bool get canPreview => trickplay != null && sheetUrl != null;
}
