import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/accounts_screen.dart';
import 'screens/join_screen.dart';
import 'screens/player_screen.dart';
import 'screens/tv_screen.dart';
import 'services/app_links.dart';
import 'services/app_update.dart';
import 'services/appearance.dart';
import 'services/backup.dart';
import 'services/downloads.dart';
import 'services/invite_link.dart';
import 'services/pip.dart';
import 'services/playback.dart';
import 'services/quality.dart';
import 'widgets/backdrop.dart';
import 'widgets/mini_player.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppearanceStore.load();
  await Playback.init();
  // Music on mobile data may come converted to a smaller size (Settings).
  await MusicQuality.init();
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
  // The music that played when the app was closed, paused, for the mini player.
  unawaited(Playback.instance.restoreQueue());
  // A friend's invite opens the app: its page comes up over whatever is on screen.
  AppLinks.listen(_openLink);
  // A newer app on the website, once the first screen has settled; at most once a day.
  Timer(const Duration(seconds: 5), _offerUpdate);
}

Future<void> _offerUpdate() async {
  // Android also starts the app without a screen, for its media service: nothing to show then.
  if (navigatorKey.currentContext == null) return;
  final update = await AppUpdate.check();
  final context = navigatorKey.currentContext;
  if (update != null && context != null && context.mounted) await offerUpdate(context, update);
}

void _openLink(String link) {
  final invite = parseInvite(link);
  if (invite == null) return;
  final nav = navigatorKey.currentState;
  if (nav == null) {
    // Started by the link: the first screen is not there yet.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLink(link));
    return;
  }
  nav.push(MaterialPageRoute(builder: (_) => JoinScreen(invite: invite)));
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
            title: 'OwnMedia',
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: messengerKey,
            theme: look.theme(dark: false, wallpaper: wallpaper),
            darkTheme: look.theme(dark: true, wallpaper: wallpaper),
            themeMode: look.brightness.mode,
            // The background goes under the mini player too: the window's own showed black there in
            // the light theme.
            builder: (context, child) => AppBackdrop(
              look: look,
              // One blur of the background for all glass panes on screen (see GlassPane).
              child: BackdropGroup(
                child: Column(children: [
                  Expanded(child: child!),
                  TvBar(
                      onOpen: (cast) => navigatorKey.currentState
                          ?.push(MaterialPageRoute(builder: (_) => TvRemoteScreen(cast: cast, start: false)))),
                  MiniPlayer(
                      onOpen: () => navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const PlayerScreen()))),
                ]),
              ),
            ),
            home: const AccountsScreen(),
          );
        },
      ),
    );
  }
}
