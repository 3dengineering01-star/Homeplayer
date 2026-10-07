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

  test('the background is kept between runs, odd values fall back to plain', () {
    const a = Appearance(backdrop: Backdrop.picture, picture: '/data/bg.jpg', show: 0.7, blur: true);
    final saved = a.toPrefs();
    final loaded = Appearance.fromPrefs((k) => saved[k]);
    expect(loaded.backdrop, Backdrop.picture);
    expect(loaded.picture, '/data/bg.jpg');
    expect(loaded.show, closeTo(0.7, 0.001));
    expect(loaded.blur, isTrue);

    final old = Appearance.fromPrefs((k) => {'backdrop': 'lava', 'backdrop_show': 'x', 'backdrop_picture': ''}[k]);
    expect(old.backdrop, Backdrop.plain);
    expect(old.picture, isNull);
    expect(old.show, 0.45);
    expect(old.blur, isFalse);
  });

  test('pages are clear only over a background there is', () {
    expect(const Appearance().seeThrough, isFalse);
    expect(const Appearance().veil, 1);
    expect(const Appearance(backdrop: Backdrop.picture).seeThrough, isFalse);
    expect(const Appearance(backdrop: Backdrop.picture, picture: '/p.jpg').seeThrough, isTrue);
    expect(const Appearance(backdrop: Backdrop.wallpaper, show: 0.8).veil, closeTo(0.2, 0.001));
    expect(const Appearance(backdrop: Backdrop.aurora, show: 0).veil, closeTo(0.9, 0.001));

    final clear = const Appearance(backdrop: Backdrop.ocean).theme(dark: false);
    expect(clear.scaffoldBackgroundColor, Colors.transparent);
    expect(const Appearance().theme(dark: false).scaffoldBackgroundColor, isNot(Colors.transparent));
  });

  test('the colour blends have colours, the others draw their own', () {
    for (final b in Backdrop.values) {
      final own = {Backdrop.plain, Backdrop.theme, Backdrop.picture, Backdrop.wallpaper}.contains(b);
      expect(b.colors.isEmpty, own, reason: b.name);
    }
  });

  test('the home screen keeps its chosen look of the libraries', () {
    const a = Appearance(libraries: LibraryLayout.circles);
    final saved = a.toPrefs();
    expect(Appearance.fromPrefs((k) => saved[k]).libraries, LibraryLayout.circles);
    expect(Appearance.fromPrefs((k) => {'home_libraries': 'carousel'}[k]).libraries, LibraryLayout.tiles);
    expect(const Appearance().libraries, LibraryLayout.tiles);
    expect(a.copyWith(palette: Palette.ruby).libraries, LibraryLayout.circles);
  });
}
