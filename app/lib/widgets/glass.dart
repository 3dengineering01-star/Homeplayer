import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/appearance.dart';

/// A pane of frosted glass, as on Apple's Liquid Glass: what lies behind it, blurred, under a
/// light [tint] (the theme's glass when null). It has thickness: lit from the top left, shaded
/// towards the bottom right, with a bright rim and a shadow under it. Without the glass style,
/// a plain rounded shape of [solid].
///
/// Many panes on one screen blur the background once between them when the app gives them a
/// [BackdropGroup] (it does, around all its pages); they must not overlap each other.
class GlassPane extends StatelessWidget {
  const GlassPane({
    super.key,
    required this.child,
    this.radius = 24,
    this.tint,
    this.solid,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final double radius;

  /// The glass's own colour, e.g. a server's colour; null for the theme's.
  final Color? tint;

  /// The colour without glass; null for the theme's card colour.
  final Color? solid;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How much what lies behind is blurred.
  static const blur = 24.0;

  @override
  Widget build(BuildContext context) {
    final look = GlassLook.from(context);
    final shape = BorderRadius.circular(radius);
    final tappable = onTap != null || onLongPress != null;
    Widget content(Widget inner) => tappable
        ? Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: onTap, onLongPress: onLongPress, borderRadius: shape, child: inner),
          )
        : inner;

    if (!look.on) {
      return Material(
        color: solid ?? Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: content(child),
      );
    }

    final pane = DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, color: tint ?? look.tint),
      child: CustomPaint(painter: _Relief(radius, look), child: content(child)),
    );
    final filter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);
    return CustomPaint(
      painter: _CastShadow(radius, look.shadow),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropGroup.of(context) == null
            ? BackdropFilter(filter: filter, child: pane)
            : BackdropFilter.grouped(filter: filter, child: pane),
      ),
    );
  }
}

/// The light and shade that give a pane its thickness.
class _Relief extends CustomPainter {
  const _Relief(this.radius, this.look);

  final double radius;
  final GlassLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    Shader slope(List<Color> colors, List<double> stops) =>
        LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors, stops: stops)
            .createShader(rect);
    canvas.drawRRect(
      shape,
      Paint()..shader = slope([look.shine, look.shine.withValues(alpha: 0), look.shade], const [0, 0.45, 1]),
    );
    // The rim: bright where the light meets it, dim along the sides, a glint at the far corner.
    final lit = look.edge.withValues(alpha: min(1, look.edge.a * 2.5));
    canvas.drawRRect(
      shape.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = slope([lit, look.edge.withValues(alpha: look.edge.a * 0.3), look.edge], const [0, 0.6, 1]),
    );
  }

  @override
  bool shouldRepaint(_Relief old) => old.radius != radius || old.look != look;
}

/// A pane's shadow, only around it: under the pane it would show through the glass as dirt.
class _CastShadow extends CustomPainter {
  const _CastShadow(this.radius, this.color);

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.save();
    canvas.clipPath(Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(48))
      ..addRRect(shape));
    canvas.drawRRect(
      shape.shift(const Offset(0, 8)),
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CastShadow old) => old.radius != radius || old.color != color;
}

/// A round badge with an icon on it. With the glass style, a glossy bead of [color] lit from
/// the top left, casting a shadow, with the icon raised off it; without, a flat disc of [flat].
class IconOrb extends StatelessWidget {
  const IconOrb({
    super.key,
    required this.icon,
    required this.color,
    required this.onColor,
    required this.flat,
    this.size = 40,
  });

  final IconData icon;
  final Color color;

  /// The icon's colour.
  final Color onColor;
  final Color flat;
  final double size;

  @override
  Widget build(BuildContext context) {
    final look = GlassLook.from(context);
    if (!look.on) {
      return CircleAvatar(radius: size / 2, backgroundColor: flat, child: Icon(icon, color: onColor, size: size * 0.54));
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, dark ? 0.4 : 0.7)!,
            color,
            Color.lerp(color, Colors.black, dark ? 0.35 : 0.14)!,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.24 : 0.8)),
        boxShadow: [BoxShadow(color: look.shadow, blurRadius: size * 0.3, offset: Offset(0, size * 0.12))],
      ),
      // The gloss: a spot of light on the side the light comes from.
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.45, -0.6),
            radius: 0.6,
            colors: [Colors.white.withValues(alpha: dark ? 0.3 : 0.6), Colors.white.withValues(alpha: 0)],
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: size * 0.54,
            color: onColor,
            shadows: [
              Shadow(color: Colors.black.withValues(alpha: dark ? 0.5 : 0.22), blurRadius: 3, offset: const Offset(0, 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}
