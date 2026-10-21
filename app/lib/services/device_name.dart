import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

/// What the server calls this kind of client in its list of devices.
String get platformName => Platform.isIOS ? 'iPhone' : 'Android';

/// The phone's model as people know it: "Google Pixel 10a", "samsung SM-S911B", "iPhone 16 Pro".
/// The owner of a server sees it in the list of who joined and where photos came from.
Future<String> deviceName() async {
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return ios.modelName.isNotEmpty ? ios.modelName : ios.model;
    }
    final android = await info.androidInfo;
    return modelWithMaker(android.manufacturer, android.model);
  } catch (_) {
    return 'Phone';
  }
}

/// [model] with the maker in front, unless the model already starts with it.
String modelWithMaker(String manufacturer, String model) {
  final maker = manufacturer.trim();
  return maker.isEmpty || model.toLowerCase().startsWith(maker.toLowerCase()) ? model : '$maker $model';
}
