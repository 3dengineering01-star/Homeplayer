import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/appearance.dart';

void main() {
  test('the chosen look survives a restart; unknown values fall back to system and wallpaper', () {
    const a = Appearance(brightness: ThemeBrightness.black, palette: Palette.ruby);
    final saved = a.toPrefs();
    final loaded = Appearance.fromPrefs((k) => saved[k]);
    expect(loaded.brightness, ThemeBrightness.black);
    expect(loaded.palette, Palette.ruby);

    final fresh = Appearance.fromPrefs((k) => {'theme_brightness': 'neon'}[k]);
    expect(fresh.brightness, ThemeBrightness.system);
    expect(fresh.palette, Palette.wallpaper);
  });

  test('black and dark both use the dark theme, system follows the phone', () {
    expect(ThemeBrightness.system.mode, ThemeMode.system);
    expect(ThemeBrightness.light.mode, ThemeMode.light);
    expect(ThemeBrightness.dark.mode, ThemeMode.dark);
    expect(ThemeBrightness.black.mode, ThemeMode.dark);
  });

  test('black has true black backgrounds, dark does not', () {
    final black = const Appearance(brightness: ThemeBrightness.black).theme(dark: true);
    final dark = const Appearance(brightness: ThemeBrightness.dark).theme(dark: true);
    expect(black.colorScheme.surface, Colors.black);
    expect(black.scaffoldBackgroundColor, Colors.black);
    expect(dark.colorScheme.surface, isNot(Colors.black));
    expect(black.colorScheme.brightness, Brightness.dark);
  });

  test('the wallpaper colour is used only with the wallpaper palette, and only when the phone has one', () {
    const wall = Color(0xFF00AA00);
    expect(const Appearance().seedFor(wall), wall);
    expect(const Appearance().seedFor(null), Palette.wallpaper.seed);
    expect(const Appearance(palette: Palette.violet).seedFor(wall), Palette.violet.seed);
  });

  test('different palettes give different main colours', () {
    final violet = const Appearance(palette: Palette.violet).theme(dark: false);
    final emerald = const Appearance(palette: Palette.emerald).theme(dark: false);
    expect(violet.colorScheme.primary, isNot(emerald.colorScheme.primary));
  });
}
