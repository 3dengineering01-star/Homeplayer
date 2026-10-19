import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
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

/// Whether this phone can show its home screen wallpaper through the app: only Android lets an
/// app's window be see-through.
bool get wallpaperBackdropAvailable => defaultTargetPlatform == TargetPlatform.android;

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
    this.glass = true,
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

  /// Liquid glass: cards, panels and the mini player as frosted, see-through glass over a
  /// colourful background, like Apple's Liquid Glass.
  final bool glass;

  /// The background actually shown: glass needs colours behind it, so with glass the plain
  /// background is the theme's blend.
  Backdrop get shown => glass && backdrop == Backdrop.plain ? Backdrop.theme : backdrop;

  /// Whether the screens let a background through instead of painting the theme's colour.
  bool get seeThrough => shown != Backdrop.plain && (shown != Backdrop.picture || picture != null);

  /// The theme's colour laid over the background: the less [show], the more of it. Glass lets
  /// more of the background through, its panels keep text readable.
  double get veil => seeThrough ? (1 - show.clamp(0.1, 1.0)) * (glass ? 0.6 : 1) : 1;

  Appearance copyWith({
    ThemeBrightness? brightness,
    Palette? palette,
    Backdrop? backdrop,
    String? picture,
    double? show,
    bool? blur,
    LibraryLayout? libraries,
    bool? glass,
  }) =>
      Appearance(
        brightness: brightness ?? this.brightness,
        palette: palette ?? this.palette,
        backdrop: backdrop ?? this.backdrop,
        picture: picture ?? this.picture,
        show: show ?? this.show,
        blur: blur ?? this.blur,
        libraries: libraries ?? this.libraries,
        glass: glass ?? this.glass,
      );

  static const _brightnessKey = 'theme_brightness';
  static const _paletteKey = 'theme_palette';
  static const _backdropKey = 'backdrop';
  static const _pictureKey = 'backdrop_picture';
  static const _showKey = 'backdrop_show';
  static const _blurKey = 'backdrop_blur';
  static const _librariesKey = 'home_libraries';
  static const _glassKey = 'theme_glass';

  Map<String, String> toPrefs() => {
        _brightnessKey: brightness.name,
        _paletteKey: palette.name,
        _backdropKey: backdrop.name,
        _pictureKey: picture ?? '',
        _showKey: show.toStringAsFixed(2),
        _blurKey: '$blur',
        _librariesKey: libraries.name,
        _glassKey: '$glass',
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
      // Glass from the start, also for those who chose their look before glass came.
      glass: read(_glassKey) != 'false',
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
    return buildTheme(scheme, seeThrough: seeThrough, glass: glass);
  }
}

/// The glass of the theme: whether panels are glass, and its tint, edge and shine. Widgets that
/// draw glass themselves ([GlassPane]) take it from here.
@immutable
class GlassLook extends ThemeExtension<GlassLook> {
  const GlassLook({
    required this.on,
    required this.tint,
    required this.edge,
    required this.shine,
    required this.shade,
    required this.shadow,
  });

  /// For [scheme]: light glass is milky, dark glass smoky.
  factory GlassLook.of(ColorScheme scheme, {required bool on}) {
    final dark = scheme.brightness == Brightness.dark;
    return GlassLook(
      on: on,
      tint: dark ? scheme.surfaceContainer.withValues(alpha: 0.42) : scheme.surface.withValues(alpha: 0.45),
      edge: Colors.white.withValues(alpha: dark ? 0.16 : 0.6),
      shine: Colors.white.withValues(alpha: dark ? 0.16 : 0.4),
      shade: Colors.black.withValues(alpha: dark ? 0.22 : 0.05),
      shadow: Colors.black.withValues(alpha: dark ? 0.4 : 0.16),
    );
  }

  static const _off = GlassLook(
    on: false,
    tint: Colors.transparent,
    edge: Colors.transparent,
    shine: Colors.transparent,
    shade: Colors.transparent,
    shadow: Colors.transparent,
  );

  /// The glass of the current theme; no glass where the theme has none.
  static GlassLook from(BuildContext context) => Theme.of(context).extension<GlassLook>() ?? _off;

  final bool on;

  /// The colour the glass adds to what is behind it.
  final Color tint;

  /// The thin bright edge around a pane.
  final Color edge;

  /// The light on a pane's top left corner, where the light falls on it.
  final Color shine;

  /// The darkening of a pane's bottom right corner, away from the light.
  final Color shade;

  /// The shadow a pane or a bead casts on what is under it.
  final Color shadow;

  @override
  GlassLook copyWith({bool? on, Color? tint, Color? edge, Color? shine, Color? shade, Color? shadow}) => GlassLook(
        on: on ?? this.on,
        tint: tint ?? this.tint,
        edge: edge ?? this.edge,
        shine: shine ?? this.shine,
        shade: shade ?? this.shade,
        shadow: shadow ?? this.shadow,
      );

  @override
  GlassLook lerp(GlassLook? other, double t) => other == null
      ? this
      : GlassLook(
          on: t < 0.5 ? on : other.on,
          tint: Color.lerp(tint, other.tint, t)!,
          edge: Color.lerp(edge, other.edge, t)!,
          shine: Color.lerp(shine, other.shine, t)!,
          shade: Color.lerp(shade, other.shade, t)!,
          shadow: Color.lerp(shadow, other.shadow, t)!,
        );
}

/// The app's theme around [scheme]: rounded cards and sheets, quieter app bars. With
/// [seeThrough] the pages are clear, so the background under them shows; an app bar gets a
/// frosted tint only once the page scrolls under it. With [glass], cards, chips and menus are
/// see-through glass with a bright edge, and corners rounder.
ThemeData buildTheme(ColorScheme scheme, {bool seeThrough = false, bool glass = false}) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme;
  final look = GlassLook.of(scheme, on: glass);
  final themed = base.copyWith(
    scaffoldBackgroundColor: seeThrough ? Colors.transparent : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: seeThrough
          ? WidgetStateColor.resolveWith((states) => states.contains(WidgetState.scrolledUnder)
              ? scheme.surfaceContainer.withValues(alpha: glass ? 0.72 : 0.9)
              : Colors.transparent)
          : scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: glass ? look.tint : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(glass ? 24 : 16),
        side: glass ? BorderSide(color: look.edge) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(glass ? 18 : 12)),
      iconColor: scheme.onSurfaceVariant,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: glass ? scheme.surfaceContainerLow.withValues(alpha: 0.94) : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(glass ? 32 : 24))),
      showDragHandle: true,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: glass
          ? StadiumBorder(side: BorderSide(color: look.edge))
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: glass ? look.tint : null,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
    ),
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      TargetPlatform.android:
          seeThrough ? const _SeeThroughTransitions() : const PredictiveBackPageTransitionsBuilder(),
      // The usual iPhone slide, except over a picture or colour blend, which must stay visible.
      TargetPlatform.iOS: seeThrough ? const _SeeThroughTransitions() : const CupertinoPageTransitionsBuilder(),
    }),
    extensions: [look],
  );
  if (!glass) return themed;
  return themed.copyWith(
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32), side: BorderSide(color: look.edge)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainer.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: look.edge)),
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: look.tint, elevation: 0),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(backgroundColor: look.tint, side: BorderSide(color: look.edge)),
    ),
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
    if (current.value.backdrop == Backdrop.wallpaper && !wallpaperBackdropAvailable) {
      current.value = current.value.copyWith(backdrop: Backdrop.plain);
    }
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
