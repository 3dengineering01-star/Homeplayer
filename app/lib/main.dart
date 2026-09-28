import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/accounts_screen.dart';
import 'screens/player_screen.dart';
import 'services/playback.dart';
import 'widgets/mini_player.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Playback.init();
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
    const seed = Color(0xFF7CC4FF);
    return MaterialApp(
      title: 'Homeplay',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      builder: (context, child) => Column(children: [
        Expanded(child: child!),
        MiniPlayer(onOpen: () => navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const PlayerScreen()))),
      ]),
      home: const AccountsScreen(),
    );
  }
}
