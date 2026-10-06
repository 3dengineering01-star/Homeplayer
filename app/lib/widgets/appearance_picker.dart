import 'package:flutter/material.dart';

import '../services/appearance.dart';

/// Light, dark or black, and the app's colours, with the change shown at once.
class AppearancePicker extends StatelessWidget {
  const AppearancePicker({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Appearance>(
        valueListenable: AppearanceStore.current,
        builder: (context, look, _) {
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeBrightness>(
                  showSelectedIcon: false,
                  segments: [
                    for (final b in ThemeBrightness.values)
                      ButtonSegment(value: b, label: Text(b.label), icon: Icon(_icon(b), size: 18)),
                  ],
                  selected: {look.brightness},
                  onSelectionChanged: (s) => AppearanceStore.set(look.copyWith(brightness: s.first)),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final p in Palette.values)
                  _Swatch(
                    palette: p,
                    selected: look.palette == p,
                    // The wallpaper swatch shows what the wallpaper gives, when it is in use.
                    color: p == Palette.wallpaper && look.palette == p ? theme.colorScheme.primary : p.seed,
                    onTap: () => AppearanceStore.set(look.copyWith(palette: p)),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(
                look.palette == Palette.wallpaper
                    ? 'Colours follow your wallpaper (Android 12 and newer).'
                    : 'Black saves battery on OLED screens.',
                style: theme.textTheme.bodySmall,
              ),
            ]),
          );
        },
      );

  static IconData _icon(ThemeBrightness b) => switch (b) {
        ThemeBrightness.system => Icons.brightness_auto,
        ThemeBrightness.light => Icons.light_mode,
        ThemeBrightness.dark => Icons.dark_mode,
        ThemeBrightness.black => Icons.contrast,
      };
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.selected, required this.color, required this.onTap});

  final Palette palette;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tones = ColorScheme.fromSeed(seedColor: color, brightness: Theme.of(context).brightness);
    return Semantics(
      button: true,
      selected: selected,
      label: palette.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 64,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 52,
              height: 52,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2.5),
              ),
              child: ClipOval(
                child: Stack(fit: StackFit.expand, children: [
                  // Three tones of the palette, as a little preview.
                  Column(children: [
                    Expanded(child: ColoredBox(color: tones.primary)),
                    Expanded(
                      child: Row(children: [
                        Expanded(child: ColoredBox(color: tones.secondaryContainer)),
                        Expanded(child: ColoredBox(color: tones.tertiary)),
                      ]),
                    ),
                  ]),
                  if (palette == Palette.wallpaper) Icon(Icons.wallpaper, color: tones.onPrimary, size: 20),
                  if (selected && palette != Palette.wallpaper) Icon(Icons.check, color: tones.onPrimary, size: 22),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Text(palette.label, style: Theme.of(context).textTheme.labelSmall, maxLines: 1),
          ]),
        ),
      ),
    );
  }
}
