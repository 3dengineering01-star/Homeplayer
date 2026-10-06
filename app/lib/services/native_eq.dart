import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_effects.dart';

/// Android's own equalizer with a limiter, on the player's audio session (see MainActivity).
class NativeEq {
  static const _channel = MethodChannel('homeplay/eq');

  /// The audio session for mpv's output; null without the activity (started by Android Auto).
  static Future<int?> session() async {
    try {
      return await _channel.invokeMethod<int>('session');
    } catch (_) {
      return null;
    }
  }

  /// Sets the bands and turns the equalizer on or off. False where Android's equalizer is not
  /// available: the player then uses its own filters.
  static Future<bool> apply({required bool enabled, required List<double> gains}) async {
    try {
      return await _channel.invokeMethod<bool>('apply', {
            'enabled': enabled,
            'gains': gains,
            'cutoffs': eqCutoffs(),
          }) ??
          false;
    } catch (e) {
      debugPrint('homeplay equalizer unavailable: $e');
      return false;
    }
  }
}
