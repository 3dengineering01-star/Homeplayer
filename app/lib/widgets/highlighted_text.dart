import 'package:flutter/material.dart';

import '../services/search_index.dart';

/// [text] with the words of [query] in it shown bold in the theme's colour.
class HighlightedText extends StatelessWidget {
  const HighlightedText(this.text, {super.key, required this.query, this.style, this.maxLines = 1});

  final String text;
  final String query;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final mark = base.copyWith(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary);
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in highlightRanges(text, query)) {
      if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
      spans.add(TextSpan(text: text.substring(start, end), style: mark));
      at = end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(style: base, children: spans), maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}
