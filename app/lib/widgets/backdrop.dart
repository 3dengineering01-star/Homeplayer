import 'dart:io';
import 'dart:ui' as ui;

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
      // The window is always clear: without the wallpaper, something solid under a picture
      // that is still loading.
      if (look.backdrop != Backdrop.wallpaper) ColoredBox(color: scheme.surface),
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
          : look.blur
              ? _SoftPicture(path: look.picture!)
              : LayoutBuilder(builder: (context, box) {
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  return Image.file(
                    File(look.picture!),
                    fit: BoxFit.cover,
                    cacheWidth: (box.maxWidth * dpr).round().clamp(1, 2400),
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

/// The picture blurred once into a small image, then stretched over the screen. A blur filter
/// on the screen would be worked out again with every frame drawn over it; stretching a tiny
/// copy without blurring it first showed as a mosaic.
class _SoftPicture extends StatefulWidget {
  const _SoftPicture({required this.path});

  final String path;

  @override
  State<_SoftPicture> createState() => _SoftPictureState();
}

class _SoftPictureState extends State<_SoftPicture> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_SoftPicture old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  Future<void> _load() async {
    final path = widget.path;
    try {
      final codec = await ui.instantiateImageCodec(await File(path).readAsBytes(), targetWidth: 160);
      final small = (await codec.getNextFrame()).image;
      codec.dispose();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImage(
        small,
        Offset.zero,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4, tileMode: TileMode.mirror),
      );
      final picture = recorder.endRecording();
      final soft = await picture.toImage(small.width, small.height);
      picture.dispose();
      small.dispose();
      if (!mounted || path != widget.path) {
        soft.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = soft;
      });
    } catch (e) {
      debugPrint('homeplay soft background failed: $e');
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image == null
      ? ColoredBox(color: Theme.of(context).colorScheme.surface)
      : RawImage(image: _image, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
}
