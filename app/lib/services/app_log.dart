import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../api/common.dart';

/// The app's last few hundred log lines, kept in memory only, for a problem report the user
/// may choose to send. Never written to disk and never sent by the app itself.
class AppLog {
  AppLog._();

  static const maxLines = 200;
  static const _maxLineLength = 300;

  static final _lines = ListQueue<String>();
  static bool _installed = false;

  /// Keeps a copy of everything that goes through [debugPrint] (the app's own `homeplay` lines
  /// and Flutter's error reports), with secrets taken out.
  static void install() {
    if (_installed) return;
    _installed = true;
    final print = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) add(message);
      print(message, wrapWidth: wrapWidth);
    };
  }

  static void add(String message, {DateTime? at}) {
    for (final line in logLines(message, at ?? DateTime.now(), maxLength: _maxLineLength)) {
      _lines.addLast(line);
      if (_lines.length > maxLines) _lines.removeFirst();
    }
  }

  /// Oldest first.
  static List<String> get lines => List.unmodifiable(_lines);

  @visibleForTesting
  static void clear() => _lines.clear();
}

/// [message] as log lines: the time in front, no secrets ([redactSecrets]), each line cut to
/// [maxLength], blank lines left out.
List<String> logLines(String message, DateTime at, {int maxLength = 300}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  return [
    for (final raw in redactSecrets(message).split('\n'))
      if (raw.trim().isNotEmpty) '$time ${raw.length > maxLength ? '${raw.substring(0, maxLength)}…' : raw}',
  ];
}
