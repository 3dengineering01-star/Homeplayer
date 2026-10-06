import 'dart:math';

import 'package:flutter/material.dart';

/// A record in the app's colours, for music without a cover. It turns while [playing].
class VinylArt extends StatefulWidget {
  const VinylArt({super.key, required this.playing});

  final bool playing;

  @override
  State<VinylArt> createState() => _VinylArtState();
}

class _VinylArtState extends State<VinylArt> with SingleTickerProviderStateMixin {
  // One turn in 4 s, a bit faster than a real 33 rpm record, which looks sluggish on screen.
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _turn.repeat();
  }

  @override
  void didUpdateWidget(VinylArt old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_turn.isAnimating) _turn.repeat();
    if (!widget.playing && _turn.isAnimating) _turn.stop();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Drawn once, then only turned: the turning is cheap for the phone.
    return RotationTransition(
      turns: _turn,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RecordPainter(label: scheme.primary, labelEdge: scheme.tertiary, onLabel: scheme.onPrimary),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _RecordPainter extends CustomPainter {
  _RecordPainter({required this.label, required this.labelEdge, required this.onLabel});

  final Color label;
  final Color labelEdge;
  final Color onLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = min(size.width, size.height) / 2;
    // The disc, with a soft sheen.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF2A2A2E), Color(0xFF111114)], stops: [0.4, 1])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Grooves.
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.004
      ..color = Colors.white.withValues(alpha: 0.06);
    for (var g = r * 0.42; g < r * 0.97; g += r * 0.025) {
      canvas.drawCircle(c, g, groove);
    }
    // A light streak across, so the turning shows.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.8),
      -pi / 3,
      pi / 5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.3
        ..color = Colors.white.withValues(alpha: 0.05),
    );
    // The label in the theme's colours.
    final labelRect = Rect.fromCircle(center: c, radius: r * 0.36);
    canvas.drawCircle(
      c,
      r * 0.36,
      Paint()..shader = LinearGradient(colors: [label, labelEdge]).createShader(labelRect),
    );
    canvas.drawCircle(c, r * 0.30, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.01
      ..color = onLabel.withValues(alpha: 0.35));
    // The note on the label and the spindle hole.
    final note = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.music_note.codePoint),
        style: TextStyle(fontSize: r * 0.3, fontFamily: Icons.music_note.fontFamily, color: onLabel),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    note.paint(canvas, c - Offset(note.width / 2, note.height / 2 + r * 0.12));
    canvas.drawCircle(c, r * 0.035, Paint()..color = const Color(0xFF111114));
  }

  @override
  bool shouldRepaint(_RecordPainter old) => old.label != label || old.labelEdge != labelEdge || old.onLabel != onLabel;
}

/// A small square in the theme's colours with a note, for lists and the mini player.
class NoteTile extends StatelessWidget {
  const NoteTile({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Center(child: Icon(Icons.music_note, size: size, color: scheme.onPrimary)),
    );
  }
}
