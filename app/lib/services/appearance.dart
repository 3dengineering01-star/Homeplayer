import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light or dark: as the phone, or fixed. Black is dark with true black backgrounds, which
/// OLED screens show by switching the pixels off.
enum ThemeBrightness {
  system('System'),
  light('Light'),
  dark('Dark'),
  black('Black');

  const ThemeBrightness(this.label);
  final String label;

  ThemeMode get mode => switch (this) {
        ThemeBrightness.system => ThemeMode.system,
        ThemeBrightness.light => ThemeMode.light,
        ThemeBrightness.dark || ThemeBrightness.black => ThemeMode.dark,
      };
}

/// The app's colours: from the wallpaper (Material You) or one of these.
enum Palette {
  wallpaper('Wallpaper', Color(0xFF7CC4FF)),
  sky('Sky', Color(0xFF7CC4FF)),
  violet('Violet', Color(0xFF8E6CF0)),
  emerald('Emerald', Color(0xFF2FA36B)),
  sunset('Sunset', Color(0xFFF08A3C)),
  ruby('Ruby', Color(0xFFD9364F)),
  rose('Rose', Color(0xFFE76FA8)),
  gold('Gold', Color(0xFFD4A62A)),
  graphite('Graphite', Color(0xFF6B7280));

  const Palette(this.label, this.seed);
  final String label;

  /// Base colour; for [wallpaper], what is used where the phone has no wallpaper colours.
  final Color seed;
}

/// How the app looks.
class Appearance {
  const Appearance({this.brightness = ThemeBrightness.system, this.palette = Palette.wallpaper});

  final ThemeBrightness brightness;
  final Palette palette;

  Appearance copyWith({ThemeBrightness? brightness, Palette? palette}) =>
      Appearance(brightness: brightness ?? this.brightness, palette: palette ?? this.palette);

  static const _brightnessKey = 'theme_brightness';
  static const _paletteKey = 'theme_palette';

  Map<String, String> toPrefs() => {_brightnessKey: brightness.name, _paletteKey: palette.name};

  static Appearance fromPrefs(Object? Function(String key) read) => Appearance(
        brightness: ThemeBrightness.values.firstWhere((b) => b.name == read(_brightnessKey), orElse: () => ThemeBrightness.system),
        palette: Palette.values.firstWhere((p) => p.name == read(_paletteKey), orElse: () => Palette.wallpaper),
      );

  /// The seed colour for [brightness]: the wallpaper's main colour when chosen and known.
  Color seedFor(Color? wallpaper) => palette == Palette.wallpaper && wallpaper != null ? wallpaper : palette.seed;

  /// The theme for light or dark ([dark]); [wallpaper] is the phone's main colour if it has one.
  ThemeData theme({required bool dark, Color? wallpaper}) {
    var scheme = ColorScheme.fromSeed(
      seedColor: seedFor(wallpaper),
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    if (dark && brightness == ThemeBrightness.black) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF121212),
        surfaceContainerHigh: const Color(0xFF1A1A1A),
        surfaceContainerHighest: const Color(0xFF222222),
      );
    }
    return buildTheme(scheme);
  }
}

/// The app's theme around [scheme]: rounded cards and sheets, quieter app bars.
ThemeData buildTheme(ColorScheme scheme) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      iconColor: scheme.onSurfaceVariant,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      showDragHandle: true,
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    }),
  );
}

/// The chosen appearance, kept between runs; the app rebuilds when it changes.
class AppearanceStore {
  AppearanceStore._();

  static final ValueNotifier<Appearance> current = ValueNotifier(const Appearance());

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    current.value = Appearance.fromPrefs(p.get);
  }

  static Future<void> set(Appearance a) async {
    current.value = a;
    final p = await SharedPreferences.getInstance();
    for (final e in a.toPrefs().entries) {
      await p.setString(e.key, e.value);
    }
  }
}
