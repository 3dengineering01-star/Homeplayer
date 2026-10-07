import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/account.dart';

class AccountStore {
  static const _storage = FlutterSecureStorage();
  static const _accountsKey = 'accounts';
  static const _deviceIdKey = 'device_id';
  static const _lastOpenedKey = 'last_opened';

  static Future<List<Account>> load() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Account.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> _save(List<Account> accounts) =>
      _storage.write(key: _accountsKey, value: jsonEncode(accounts.map((a) => a.toJson()).toList()));

  static Future<void> add(Account account) async {
    final accounts = await load();
    accounts.removeWhere((a) => a.id == account.id);
    accounts.add(account);
    await _save(accounts);
  }

  static Future<void> remove(String id) async {
    final accounts = await load();
    accounts.removeWhere((a) => a.id == id);
    await _save(accounts);
  }

  /// The server opened last, which the app opens again on start.
  static Future<String?> lastOpened() => _storage.read(key: _lastOpenedKey);

  static Future<void> setLastOpened(String id) => _storage.write(key: _lastOpenedKey, value: id);

  /// Stable per-install id; Jellyfin uses it to tell sessions apart.
  static Future<String> deviceId() async {
    var id = await _storage.read(key: _deviceIdKey);
    if (id == null) {
      id = randomHex(16);
      await _storage.write(key: _deviceIdKey, value: id);
    }
    return id;
  }
}

String randomHex(int bytes) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
