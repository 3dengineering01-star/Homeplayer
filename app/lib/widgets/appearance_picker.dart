import 'package:flutter/material.dart';

import '../services/appearance.dart';
import 'backdrop.dart';

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
                      // The icon goes with the label only where there is room: "System" wrapped.
                      ButtonSegment(
                        value: b,
                        tooltip: b.label,
                        label: Text(b.label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                      ),
                  ],
                  selected: {look.brightness},
                  onSelectionChanged: (s) => AppearanceStore.set(look.copyWith(brightness: s.first)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Black saves battery on OLED screens.', style: theme.textTheme.bodySmall),
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
              if (look.palette == Palette.wallpaper)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Colours follow your wallpaper (Android 12 and newer).', style: theme.textTheme.bodySmall),
                ),
              const SizedBox(height: 20),
              Text('Libraries on the home screen', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<LibraryLayout>(
                  showSelectedIcon: false,
                  segments: [
                    for (final l in LibraryLayout.values)
                      ButtonSegment(value: l, icon: Icon(l.icon), label: Text(l.label, maxLines: 1, softWrap: false)),
                  ],
                  selected: {look.libraries},
                  onSelectionChanged: (s) => AppearanceStore.set(look.copyWith(libraries: s.first)),
                ),
              ),
              const SizedBox(height: 20),
              Text('Background', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 12, children: [
                for (final b in Backdrop.values)
                  _BackdropChoice(
                    look: look,
                    backdrop: b,
                    onTap: () => _choose(context, look, b),
                  ),
              ]),
              if (look.backdrop == Backdrop.picture && look.picture != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _pick(context),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Another picture'),
                  ),
                ),
              if (look.backdrop == Backdrop.wallpaper)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Your home screen wallpaper shows through the app.', style: theme.textTheme.bodySmall),
                ),
              if (look.seeThrough) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Text('Background strength', style: theme.textTheme.bodyMedium),
                  Expanded(
                    child: Slider(
                      value: look.show,
                      min: 0.1,
                      max: 1,
                      onChanged: (v) => AppearanceStore.preview(look.copyWith(show: v)),
                      onChangeEnd: (v) => AppearanceStore.set(look.copyWith(show: v)),
                    ),
                  ),
                ]),
                if (look.backdrop == Backdrop.picture)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Soften the picture'),
                    subtitle: const Text('Blurred, so text over it reads easier'),
                    value: look.blur,
                    onChanged: (v) => AppearanceStore.set(look.copyWith(blur: v)),
                  ),
              ],
            ]),
          );
        },
      );
}

Future<void> _choose(BuildContext context, Appearance look, Backdrop b) async {
  // The picture tile picks one the first time, and goes back to the one picked later on.
  if (b == Backdrop.picture && look.picture == null) return _pick(context);
  await AppearanceStore.set(look.copyWith(backdrop: b));
}

Future<void> _pick(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await AppearanceStore.pickPicture();
  } catch (e) {
    debugPrint('homeplay background picture failed: $e');
    messenger?.showSnackBar(const SnackBar(content: Text('Could not use that picture')));
  }
}

/// A small upright preview of a background with its name, outlined when chosen.
class _BackdropChoice extends StatelessWidget {
  const _BackdropChoice({required this.look, required this.backdrop, required this.onTap});

  final Appearance look;
  final Backdrop backdrop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = look.backdrop == backdrop;
    final icon = switch (backdrop) {
      Backdrop.wallpaper => Icons.wallpaper,
      Backdrop.picture when look.picture == null => Icons.add_photo_alternate_outlined,
      _ => null,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: backdrop.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 64,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 84,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2.5 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(fit: StackFit.expand, children: [
                  Container(color: backdrop == Backdrop.plain ? scheme.surface : scheme.surfaceContainerHighest),
                  if (backdrop != Backdrop.plain && backdrop != Backdrop.wallpaper)
                    BackdropLayer(look: look.copyWith(backdrop: backdrop, blur: false)),
                  if (icon != null) Icon(icon, color: scheme.onSurfaceVariant),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Text(backdrop.label, style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
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
                  // Containers, not bare ColoredBoxes: those have no size of their own here.
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: Container(color: tones.primary)),
                    Expanded(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: Container(color: tones.secondaryContainer)),
                        Expanded(child: Container(color: tones.tertiary)),
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

/// The theme and colours in a sheet, for the players: the change shows at once behind it.
void showAppearanceSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          ),
          const AppearancePicker(),
        ]),
      ),
    ),
  );
}
