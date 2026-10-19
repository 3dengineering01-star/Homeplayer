import 'package:flutter/material.dart';

/// A strip of letters at the side of a long list: touching or sliding along it calls [onLetter]
/// with the letter's place in [letters], and a big copy of the letter shows beside the finger.
class AlphabetBar extends StatefulWidget {
  const AlphabetBar({super.key, required this.letters, required this.onLetter});

  final List<String> letters;
  final ValueChanged<int> onLetter;

  @override
  State<AlphabetBar> createState() => _AlphabetBarState();
}

class _AlphabetBarState extends State<AlphabetBar> {
  int? _at;
  double _y = 0;

  void _touch(double y, double height) {
    final n = widget.letters.length;
    final i = (y / height * n).floor().clamp(0, n - 1);
    _y = y.clamp(0, height);
    if (i == _at) return;
    setState(() => _at = i);
    widget.onLetter(i);
  }

  void _release() => setState(() => _at = null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final height = box.maxHeight;
      final cell = height / widget.letters.length;
      // Small letters when there are many (Latin, Cyrillic and digits), never larger than 12.
      final size = (cell * 0.75).clamp(6.0, 12.0);
      return Stack(clipBehavior: Clip.none, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _touch(d.localPosition.dy, height),
          onTapUp: (_) => _release(),
          onVerticalDragStart: (d) => _touch(d.localPosition.dy, height),
          onVerticalDragUpdate: (d) => _touch(d.localPosition.dy, height),
          onVerticalDragEnd: (_) => _release(),
          onVerticalDragCancel: _release,
          child: SizedBox(
            width: 24,
            height: height,
            child: Column(children: [
              for (final (i, l) in widget.letters.indexed)
                SizedBox(
                  height: cell,
                  child: Center(
                    child: Text(l,
                        // The bar measures itself; the phone's text size must not overflow it.
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: size,
                          fontWeight: FontWeight.w600,
                          color: i == _at ? scheme.primary : scheme.onSurfaceVariant,
                        )),
                  ),
                ),
            ]),
          ),
        ),
        if (_at != null)
          Positioned(
            right: 40,
            top: (_y - 32).clamp(0, height - 64),
            child: IgnorePointer(
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                child: Text(widget.letters[_at!],
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
              ),
            ),
          ),
      ]);
    });
  }
}
