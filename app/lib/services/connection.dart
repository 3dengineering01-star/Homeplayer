import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the phone has any network, as Android says. Lets the app tell "no connection at
/// all" (airplane mode) from "the server does not answer", and not wait on a server it cannot
/// reach.
class Connection {
  Connection._();

  /// True while the phone has no network. False until known, and where it cannot be known
  /// (tests).
  static final offline = ValueNotifier<bool>(false);

  static StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Starts following the network; safe to call more than once.
  static void start() {
    if (_sub != null) return;
    try {
      _sub = Connectivity().onConnectivityChanged.listen(
            (r) => offline.value = isOfflineResult(r),
            onError: (Object e) => debugPrint('homeplay connectivity: $e'),
          );
    } catch (e) {
      debugPrint('homeplay connectivity: $e');
    }
    unawaited(check());
  }

  /// Asks Android now. Never takes long and never throws: when it cannot tell, the phone
  /// counts as online, so the app tries the server as before.
  static Future<bool> check() async {
    try {
      final r = await Connectivity().checkConnectivity().timeout(const Duration(seconds: 2));
      return offline.value = isOfflineResult(r);
    } catch (_) {
      return offline.value;
    }
  }
}

/// No network of any kind. A VPN alone (Tailscale) counts as a network.
bool isOfflineResult(List<ConnectivityResult> r) => r.isNotEmpty && r.every((c) => c == ConnectivityResult.none);
