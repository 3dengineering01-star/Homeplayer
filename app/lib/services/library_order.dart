import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The order of a server's libraries on its front page and which of them are hidden, as the
/// person set them; one per server account, kept on the phone.
class LibraryOrder {
  const LibraryOrder({this.order = const [], this.hidden = const {}});

  /// Library ids in the order chosen. Libraries not in it (new on the server) come after them,
  /// in the server's order.
  final List<String> order;

  /// Library ids not shown.
  final Set<String> hidden;

  bool get isDefault => order.isEmpty && hidden.isEmpty;

  /// [items] in this order, without the hidden ones unless [withHidden].
  List<T> arrange<T>(List<T> items, String Function(T) idOf, {bool withHidden = false}) {
    final place = {for (final (i, id) in order.indexed) id: i};
    final known = [for (final it in items) if (place.containsKey(idOf(it))) it]
      ..sort((a, b) => place[idOf(a)]!.compareTo(place[idOf(b)]!));
    final fresh = [for (final it in items) if (!place.containsKey(idOf(it))) it];
    return [
      for (final it in [...known, ...fresh])
        if (withHidden || !hidden.contains(idOf(it))) it,
    ];
  }

  /// The same with [ids] (all of the server's libraries, in the new order) and [hidden].
  LibraryOrder copyWith({List<String>? order, Set<String>? hidden}) =>
      LibraryOrder(order: order ?? this.order, hidden: hidden ?? this.hidden);

  String encode() => jsonEncode({'order': order, 'hidden': hidden.toList()..sort()});

  /// What [text] holds; the default for nothing or something unreadable.
  static LibraryOrder decode(String? text) {
    if (text == null) return const LibraryOrder();
    try {
      final j = jsonDecode(text);
      if (j is! Map) return const LibraryOrder();
      List<String> strings(Object? v) => v is List ? [for (final s in v) if (s is String) s] : const [];
      return LibraryOrder(order: strings(j['order']), hidden: strings(j['hidden']).toSet());
    } catch (_) {
      return const LibraryOrder();
    }
  }

  static String _key(String accountId) => 'home.libraries.$accountId';

  static Future<LibraryOrder> load(String accountId) async =>
      decode((await SharedPreferences.getInstance()).getString(_key(accountId)));

  Future<void> save(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    isDefault ? await prefs.remove(_key(accountId)) : await prefs.setString(_key(accountId), encode());
  }

  /// Forgets it for a server removed from the app.
  static Future<void> forget(String accountId) async => (await SharedPreferences.getInstance()).remove(_key(accountId));
}
