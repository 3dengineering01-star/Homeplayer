import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Links that open the app (a friend's invite) and Android's share sheet.
class AppLinks {
  AppLinks._();

  static const _channel = MethodChannel('homeplay/links');

  /// Calls [onLink] with the link the app was started with, and with every link that comes
  /// while it runs.
  static Future<void> listen(void Function(String link) onLink) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) onLink(call.arguments as String);
    });
    try {
      final start = await _channel.invokeMethod<String>('start');
      if (start != null) onLink(start);
    } on MissingPluginException {
      // Not on Android (tests).
    } catch (e) {
      debugPrint('homeplay links: $e');
    }
  }

  /// Shares [text] through Android's share sheet.
  static Future<void> share(String text, {String title = 'Share'}) =>
      _channel.invokeMethod('share', {'text': text, 'title': title});
}
