import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
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

/// What lies behind the screens: the theme's plain colour, a colour blend, the user's own
/// picture, or the phone's home screen wallpaper seen through the app.
enum Backdrop {
  plain('Plain', []),
  theme('Theme', []),
  aurora('Aurora', [Color(0xFF00C9A7), Color(0xFF2C73D2), Color(0xFF845EC2)]),
  sunset('Sunset', [Color(0xFFFFC371), Color(0xFFFF6A88), Color(0xFF8E44AD)]),
  ocean('Ocean', [Color(0xFF6DD5ED), Color(0xFF2193B0), Color(0xFF1C3F94)]),
  forest('Forest', [Color(0xFFB8E994), Color(0xFF38A169), Color(0xFF134E5E)]),
  night('Night', [Color(0xFF2C5364), Color(0xFF203A43), Color(0xFF0F2027)]),
  picture('Picture', []),
  wallpaper('Home screen', []);

  const Backdrop(this.label, this.colors);
  final String label;

  /// A fixed blend's colours, top left to bottom right; empty for the others.
  final List<Color> colors;
}

/// How the home screen shows the server's libraries.
enum LibraryLayout {
  tiles('Tiles', Icons.grid_view),
  list('List', Icons.view_list),
  circles('Circles', Icons.apps);

  const LibraryLayout(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// How the app looks.
class Appearance {
  const Appearance({
    this.brightness = ThemeBrightness.system,
    this.palette = Palette.wallpaper,
    this.backdrop = Backdrop.plain,
    this.picture,
    this.show = 0.45,
    this.blur = false,
    this.libraries = LibraryLayout.tiles,
  });

  final ThemeBrightness brightness;
  final Palette palette;
  final Backdrop backdrop;

  /// The user's picture for [Backdrop.picture], copied into the app's own files.
  final String? picture;

  /// How much of the background shows through the theme's colour, 0.1 to 1 (fully).
  final double show;

  /// The picture softened, so text over it reads easier.
  final bool blur;

  final LibraryLayout libraries;

  /// Whether the screens let a background through instead of painting the theme's colour.
  bool get seeThrough => backdrop != Backdrop.plain && (backdrop != Backdrop.picture || picture != null);

  /// The theme's colour laid over the background: the less [show], the more of it.
  double get veil => seeThrough ? 1 - show.clamp(0.1, 1.0) : 1;

  Appearance copyWith({
    ThemeBrightness? brightness,
    Palette? palette,
    Backdrop? backdrop,
    String? picture,
    double? show,
    bool? blur,
    LibraryLayout? libraries,
  }) =>
      Appearance(
        brightness: brightness ?? this.brightness,
        palette: palette ?? this.palette,
        backdrop: backdrop ?? this.backdrop,
        picture: picture ?? this.picture,
        show: show ?? this.show,
        blur: blur ?? this.blur,
        libraries: libraries ?? this.libraries,
      );

  static const _brightnessKey = 'theme_brightness';
  static const _paletteKey = 'theme_palette';
  static const _backdropKey = 'backdrop';
  static const _pictureKey = 'backdrop_picture';
  static const _showKey = 'backdrop_show';
  static const _blurKey = 'backdrop_blur';
  static const _librariesKey = 'home_libraries';

  Map<String, String> toPrefs() => {
        _brightnessKey: brightness.name,
        _paletteKey: palette.name,
        _backdropKey: backdrop.name,
        _pictureKey: picture ?? '',
        _showKey: show.toStringAsFixed(2),
        _blurKey: '$blur',
        _librariesKey: libraries.name,
      };

  static Appearance fromPrefs(Object? Function(String key) read) {
    final picture = read(_pictureKey) as String?;
    return Appearance(
      brightness: ThemeBrightness.values.firstWhere((b) => b.name == read(_brightnessKey), orElse: () => ThemeBrightness.system),
      palette: Palette.values.firstWhere((p) => p.name == read(_paletteKey), orElse: () => Palette.wallpaper),
      backdrop: Backdrop.values.firstWhere((b) => b.name == read(_backdropKey), orElse: () => Backdrop.plain),
      picture: picture == null || picture.isEmpty ? null : picture,
      show: (double.tryParse('${read(_showKey)}') ?? 0.45).clamp(0.1, 1.0),
      blur: read(_blurKey) == 'true',
      libraries: LibraryLayout.values.firstWhere((l) => l.name == read(_librariesKey), orElse: () => LibraryLayout.tiles),
    );
  }

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
    return buildTheme(scheme, seeThrough: seeThrough);
  }
}

/// The app's theme around [scheme]: rounded cards and sheets, quieter app bars. With
/// [seeThrough] the pages are clear, so the background under them shows; an app bar gets a
/// frosted tint only once the page scrolls under it.
ThemeData buildTheme(ColorScheme scheme, {bool seeThrough = false}) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: seeThrough ? Colors.transparent : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: seeThrough
          ? WidgetStateColor.resolveWith((states) => states.contains(WidgetState.scrolledUnder)
              ? scheme.surfaceContainer.withValues(alpha: 0.9)
              : Colors.transparent)
          : scheme.surface,
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
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      TargetPlatform.android:
          seeThrough ? const _SeeThroughTransitions() : const PredictiveBackPageTransitionsBuilder(),
    }),
  );
}

/// Android's page transitions for clear pages. By default the page underneath sits on a block
/// of the theme's colour while another page comes in, which hid the background for a moment;
/// and two clear pages at once showed through each other. Here the page underneath fades away
/// as the new one comes, and back in as the back gesture uncovers it.
class _SeeThroughTransitions extends PageTransitionsBuilder {
  const _SeeThroughTransitions();

  static const _inner = PredictiveBackPageTransitionsBuilder(fallbackColor: Colors.transparent);

  @override
  Duration get transitionDuration => _inner.transitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _inner.buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        FadeTransition(opacity: ReverseAnimation(secondaryAnimation), child: child),
      );
}

/// The chosen appearance, kept between runs; the app rebuilds when it changes.
class AppearanceStore {
  AppearanceStore._();

  static final ValueNotifier<Appearance> current = ValueNotifier(const Appearance());

  static const _window = MethodChannel('homeplay/window');

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    current.value = Appearance.fromPrefs(p.get);
    if (current.value.backdrop == Backdrop.picture &&
        current.value.picture != null &&
        !File(current.value.picture!).existsSync()) {
      current.value = current.value.copyWith(backdrop: Backdrop.plain);
    }
    unawaited(_showWallpaper(current.value.backdrop == Backdrop.wallpaper));
  }

  /// Shows [a] without keeping it, e.g. while a slider moves; [set] keeps it.
  static void preview(Appearance a) => current.value = a;

  static Future<void> set(Appearance a) async {
    final wallpaperChanged = (a.backdrop == Backdrop.wallpaper) != (current.value.backdrop == Backdrop.wallpaper);
    current.value = a;
    final p = await SharedPreferences.getInstance();
    for (final e in a.toPrefs().entries) {
      await p.setString(e.key, e.value);
    }
    if (wallpaperChanged) await _showWallpaper(a.backdrop == Backdrop.wallpaper);
  }

  /// Lets the home screen wallpaper show through the window, or not.
  static Future<void> _showWallpaper(bool show) async {
    try {
      await _window.invokeMethod('showWallpaper', show);
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException catch (e) {
      debugPrint('homeplay wallpaper switch failed: $e');
    }
  }

  /// Asks for a picture from the phone's gallery and makes it the background. False when the
  /// user picked nothing.
  static Future<bool> pickPicture() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400);
    if (picked == null) return false;
    // A copy of its own: the gallery's file may go away, and the picker's copy is temporary.
    final dir = await getApplicationSupportDirectory();
    final name = 'backdrop-${DateTime.now().millisecondsSinceEpoch}${_extension(picked.path)}';
    final copy = await File(picked.path).copy('${dir.path}/$name');
    for (final old in dir.listSync().whereType<File>()) {
      if (old.uri.pathSegments.last.startsWith('backdrop-') && old.path != copy.path) {
        try {
          old.deleteSync();
        } on FileSystemException {
          // Left for the next time.
        }
      }
    }
    // A new file name, so the old picture is not shown from the image cache.
    await set(current.value.copyWith(backdrop: Backdrop.picture, picture: copy.path));
    return true;
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    return dot > path.lastIndexOf('/') ? path.substring(dot) : '.jpg';
  }
}
