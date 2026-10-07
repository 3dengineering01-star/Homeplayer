import 'dart:io';

import 'package:flutter/material.dart';

import '../services/appearance.dart';

/// The chosen background behind the whole app, with the theme's colour veiled over it so text
/// stays readable. With the plain background, just the theme's colour.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.look, required this.child});

  final Appearance look;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!look.seeThrough) return ColoredBox(color: scheme.surface, child: child);
    return Stack(fit: StackFit.expand, children: [
      // Drawn once and kept: nothing in it moves, so playback never waits on it.
      RepaintBoundary(child: BackdropLayer(look: look)),
      ColoredBox(color: scheme.surface.withValues(alpha: look.veil)),
      child,
    ]);
  }
}

/// The background itself, without the veil: also the preview in the settings.
class BackdropLayer extends StatelessWidget {
  const BackdropLayer({super.key, required this.look});

  final Appearance look;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (look.backdrop) {
      // The window is clear and Android shows the wallpaper under it.
      Backdrop.wallpaper || Backdrop.plain => const SizedBox.expand(),
      Backdrop.theme => _Blend(colors: [scheme.primaryContainer, scheme.tertiaryContainer, scheme.secondaryContainer]),
      Backdrop.picture => look.picture == null
          ? ColoredBox(color: scheme.surface)
          : LayoutBuilder(builder: (context, box) {
              final dpr = MediaQuery.devicePixelRatioOf(context);
              // Softened by decoding it tiny and stretching it back: a blur filter would be
              // worked out again with every frame drawn over it.
              final width = look.blur ? 48 : (box.maxWidth * dpr).round().clamp(1, 2400);
              return Image.file(
                File(look.picture!),
                fit: BoxFit.cover,
                cacheWidth: width,
                filterQuality: look.blur ? FilterQuality.medium : FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => ColoredBox(color: scheme.surface),
              );
            }),
      _ => _Blend(colors: look.backdrop.colors),
    };
  }
}

/// Colours flowing from the top left corner to the bottom right, with a soft light at the top.
class _Blend extends StatelessWidget {
  const _Blend({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.6, -0.8),
              radius: 1.1,
              colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      );
}
