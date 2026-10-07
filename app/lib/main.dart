import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/accounts_screen.dart';
import 'screens/player_screen.dart';
import 'services/appearance.dart';
import 'services/backup.dart';
import 'services/downloads.dart';
import 'services/pip.dart';
import 'services/playback.dart';
import 'widgets/backdrop.dart';
import 'widgets/mini_player.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppearanceStore.load();
  await Playback.init();
  await Backup.init();
  // Picks up downloads that went on while the app was closed.
  await Downloads.instance.init();
  // Closing the small video window ends the video, as leaving the player screen does.
  Pip.instance
    ..init()
    ..onClosed = Playback.instance.stop;
  // Why another audio track or a server conversion was used.
  Playback.instance.notices.listen((text) => messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6))));
  runApp(const HomeplayApp());
}

class HomeplayApp extends StatelessWidget {
  const HomeplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The phone's wallpaper colours (Android 12+), for the Wallpaper palette.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => ValueListenableBuilder<Appearance>(
        valueListenable: AppearanceStore.current,
        builder: (context, look, _) {
          final wallpaper = lightDynamic?.primary;
          return MaterialApp(
            title: 'Homeplay',
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: messengerKey,
            theme: look.theme(dark: false, wallpaper: wallpaper),
            darkTheme: look.theme(dark: true, wallpaper: wallpaper),
            themeMode: look.brightness.mode,
            // The background goes under the mini player too: the window's own showed black there in
            // the light theme.
            builder: (context, child) => AppBackdrop(
              look: look,
              child: Column(children: [
                Expanded(child: child!),
                MiniPlayer(
                    onOpen: () => navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const PlayerScreen()))),
              ]),
            ),
            home: const AccountsScreen(),
          );
        },
      ),
    );
  }
}
