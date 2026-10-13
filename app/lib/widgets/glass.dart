import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/appearance.dart';

/// A pane of frosted glass, as on Apple's Liquid Glass: what lies behind it, blurred, under a
/// light [tint] (the theme's glass when null), with a thin bright edge and a soft shine along
/// the top. Without the glass style, a plain rounded shape of [solid].
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
      decoration: BoxDecoration(
        borderRadius: shape,
        color: tint ?? look.tint,
        border: Border.all(color: look.edge),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, 0.1),
            colors: [look.shine, look.shine.withValues(alpha: 0)],
          ),
        ),
        child: content(child),
      ),
    );
    final filter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropGroup.of(context) == null
          ? BackdropFilter(filter: filter, child: pane)
          : BackdropFilter.grouped(filter: filter, child: pane),
    );
  }
}
