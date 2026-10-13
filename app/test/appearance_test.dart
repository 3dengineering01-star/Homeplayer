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
    final black = const Appearance(brightness: ThemeBrightness.black, glass: false).theme(dark: true);
    final dark = const Appearance(brightness: ThemeBrightness.dark, glass: false).theme(dark: true);
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
    expect(const Appearance(glass: false).seeThrough, isFalse);
    expect(const Appearance(glass: false).veil, 1);
    expect(const Appearance(backdrop: Backdrop.picture, glass: false).seeThrough, isFalse);
    expect(const Appearance(backdrop: Backdrop.picture, picture: '/p.jpg').seeThrough, isTrue);
    expect(const Appearance(backdrop: Backdrop.wallpaper, show: 0.8, glass: false).veil, closeTo(0.2, 0.001));
    expect(const Appearance(backdrop: Backdrop.aurora, show: 0, glass: false).veil, closeTo(0.9, 0.001));

    final clear = const Appearance(backdrop: Backdrop.ocean).theme(dark: false);
    expect(clear.scaffoldBackgroundColor, Colors.transparent);
    expect(const Appearance(glass: false).theme(dark: false).scaffoldBackgroundColor, isNot(Colors.transparent));
  });

  // Liquid glass, the look from the start: see-through glass panes over a colourful background.
  test('glass is on from the start and kept; it shows a background even when plain was chosen', () {
    expect(const Appearance().glass, isTrue);
    expect(Appearance.fromPrefs((_) => null).glass, isTrue, reason: 'saved before glass came');
    final off = const Appearance(glass: false).toPrefs();
    expect(Appearance.fromPrefs((k) => off[k]).glass, isFalse);

    expect(const Appearance().shown, Backdrop.theme);
    expect(const Appearance().seeThrough, isTrue);
    expect(const Appearance(glass: false).shown, Backdrop.plain);
    expect(const Appearance(backdrop: Backdrop.aurora).shown, Backdrop.aurora);
    // More of the background shows through glass.
    expect(const Appearance(backdrop: Backdrop.aurora, show: 0.5).veil, closeTo(0.3, 0.001));
  });

  test('with glass, cards are see-through with a bright edge; without, solid', () {
    final glass = const Appearance().theme(dark: false);
    final look = glass.extension<GlassLook>()!;
    expect(look.on, isTrue);
    expect(glass.cardTheme.color!.a, lessThan(1));
    expect((glass.cardTheme.shape! as RoundedRectangleBorder).side.color, look.edge);

    final solid = const Appearance(glass: false).theme(dark: true);
    expect(solid.extension<GlassLook>()!.on, isFalse);
    expect(solid.cardTheme.color!.a, 1);
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
