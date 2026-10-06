import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Picture-in-picture: the video keeps playing in a small window over other apps.
class Pip {
  Pip._();

  static final instance = Pip._();

  static const _channel = MethodChannel('homeplay/pip');

  /// True while the app shows as the small window; the video screen hides its controls then.
  final ValueNotifier<bool> active = ValueNotifier(false);

  /// Called when the user closes the small window.
  VoidCallback? onClosed;

  bool? _available;

  void init() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'changed':
          active.value = call.arguments == true;
        case 'closed':
          active.value = false;
          onClosed?.call();
      }
    });
  }

  /// Whether this phone has picture-in-picture (Android 8+, and not turned off by the maker).
  Future<bool> available() async {
    try {
      return _available ??= await _channel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shrinks the app to the small window now, shaped [width] × [height].
  Future<bool> enter({int? width, int? height}) async {
    try {
      return await _channel.invokeMethod<bool>('enter', {'width': width, 'height': height}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether leaving the app (home, recent apps) shrinks it to the small window.
  Future<void> setAuto(bool enabled, {int? width, int? height}) async {
    try {
      await _channel.invokeMethod('setAuto', {'enabled': enabled, 'width': width, 'height': height});
    } catch (_) {
      // No activity (Android Auto) or no picture-in-picture: nothing to do.
    }
  }
}
