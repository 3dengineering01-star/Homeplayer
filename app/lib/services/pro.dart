import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/jellyfin.dart';
import '../models/account.dart';
import 'account_store.dart';
import 'licence.dart';

/// Where OwnMedia Pro stands on this phone.
@immutable
class ProStatus {
  const ProStatus({this.enforced = false, this.bought = false, this.trialLeft = trialDays, this.price});

  /// Whether the purchase can be made here; until then nothing is locked.
  final bool enforced;

  /// Bought with this phone's Google account.
  final bool bought;

  /// Days of the free month left.
  final int trialLeft;

  /// The price as Google Play shows it here ("9,99 €"); null while unknown.
  final String? price;

  /// Whether the trial counts down: shown to the person, who has not bought.
  bool get onTrial => enforced && !bought && trialLeft > 0;

  /// Over: the free month ended and nothing was bought.
  bool get ended => enforced && !bought && trialLeft == 0;
}

/// OwnMedia Pro: the free month, the purchase on Google Play, and the purchases owners leave on
/// their servers for invited friends (see licence.dart for the rules). Only the [ProFeature]s
/// close after the free month; watching and listening never do.
class Pro {
  Pro._();

  static final instance = Pro._();

  /// A separate one, for tests.
  @visibleForTesting
  factory Pro.forTest() => Pro._();

  static const _trialKey = 'pro.trial_start';
  static const _seenKey = 'pro.last_seen';
  static const _dataKey = 'pro.purchase';
  static const _signatureKey = 'pro.signature';
  static const _storeKey = 'pro.store_seen';
  static const _paidServersKey = 'pro.paid_servers';

  final status = ValueNotifier(const ProStatus());

  /// What to tell the person about a purchase: done, waiting for the payment, failed.
  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  SharedPreferences? _prefs;
  DateTime? _trialStart;
  SignedPurchase? _purchase;
  ProductDetails? _product;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  // Servers left with the purchase this run; servers found paid by their owner.
  final Set<String> _keptOn = {};

  /// Reads what this phone knows. Enough for the background (photo backup, the car), where the
  /// store is not asked.
  Future<SharedPreferences> _load() async {
    final cached = _prefs;
    if (cached != null) return cached;
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    final now = DateTime.now();
    final start = DateTime.tryParse(p.getString(_trialKey) ?? '');
    if (start == null) await p.setString(_trialKey, now.toIso8601String());
    _trialStart = start ?? now;
    final data = p.getString(_dataKey);
    final signature = p.getString(_signatureKey);
    if (data != null && signature != null) _purchase = (data: data, signature: signature);
    _publish();
    return p;
  }

  /// At the start of the app: the price, and purchases made before (another phone with the same
  /// Google account, or before the app was installed again).
  Future<void> start() async {
    await _load();
    // Google Play only: the App Store is not set up, and an iPhone is not locked.
    if (!Platform.isAndroid || _sub != null) return;
    try {
      final iap = InAppPurchase.instance;
      _sub = iap.purchaseStream.listen(_onPurchases, onError: (Object e) => debugPrint('homeplay pro: $e'));
      if (!await iap.isAvailable()) return;
      final found = await iap.queryProductDetails({proProductId});
      if (found.productDetails.isNotEmpty) {
        _product = found.productDetails.first;
        // The free month starts the first time it can be bought here, not at the app's first
        // start: whoever used it before gets a whole month too. From now on it counts, even offline.
        final prefs = _prefs!;
        final seenBefore = prefs.getBool(_storeKey) ?? false;
        if (!seenBefore) {
          final start = trialStart(
              stored: DateTime.tryParse(prefs.getString(_trialKey) ?? ''), storeSeenBefore: false, now: DateTime.now());
          await prefs.setString(_trialKey, start.toIso8601String());
          _trialStart = start;
        }
        await prefs.setBool(_storeKey, true);
      }
      _publish();
      await _refresh();
    } catch (e) {
      debugPrint('homeplay pro: $e');
    }
  }

  // What Google Play has on this account: a purchase made elsewhere, or none after a refund.
  Future<void> _refresh() async {
    final past = await InAppPurchase.instance
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
        .queryPastPurchases();
    if (past.error != null) return;
    final pro = past.pastPurchases.where((p) => p.productID == proProductId).firstOrNull;
    if (pro != null) {
      await _take(pro);
    } else if (_purchase != null) {
      // Refunded or cancelled.
      _purchase = null;
      await _prefs!.remove(_dataKey);
      await _prefs!.remove(_signatureKey);
      _publish();
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != proProductId) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _take(p);
          if (p.status == PurchaseStatus.purchased) _messages.add('Thank you! OwnMedia Pro is yours.');
        case PurchaseStatus.pending:
          _messages.add('Waiting for the payment. OwnMedia Pro opens once Google Play confirms it.');
        case PurchaseStatus.error:
          _messages.add('The purchase did not go through: ${p.error?.message ?? 'unknown error'}');
        case PurchaseStatus.canceled:
          break;
      }
      // Google refunds a purchase that is not confirmed within three days.
      if (p.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (e) {
          debugPrint('homeplay pro: $e');
        }
      }
    }
  }

  Future<void> _take(PurchaseDetails p) async {
    if (p is! GooglePlayPurchaseDetails) return;
    final w = p.billingClientPurchase;
    if (w.purchaseState != PurchaseStateWrapper.purchased) return;
    final signed = (data: w.originalJson, signature: w.signature);
    _purchase = signed;
    final prefs = await _load();
    await prefs.setString(_dataKey, signed.data);
    await prefs.setString(_signatureKey, signed.signature);
    _publish();
    // Friends invited to the owner's servers watch free from now on.
    unawaited(_keepOnAll());
  }

  bool get _bought {
    final p = _purchase;
    if (p == null) return false;
    // With the key the purchase must carry Google's signature (a faked store cannot make one).
    return googlePlayKey.isEmpty ? isProData(p.data) : isProPurchase(p);
  }

  void _publish() {
    final p = _prefs;
    final start = _trialStart;
    if (p == null || start == null) return;
    final now = DateTime.now();
    final seen = DateTime.tryParse(p.getString(_seenKey) ?? '');
    if (seen == null || now.isAfter(seen)) p.setString(_seenKey, now.toIso8601String());
    status.value = ProStatus(
      enforced: Platform.isAndroid && (p.getBool(_storeKey) ?? false),
      bought: _bought,
      trialLeft: trialDaysLeft(start, now, lastSeen: seen),
      price: _product?.price,
    );
  }

  /// Opens Google Play's purchase sheet.
  Future<void> buy() async {
    final product = _product;
    if (product == null) {
      _messages.add('Google Play is not available on this phone.');
      return;
    }
    try {
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      _messages.add('Google Play could not start the purchase. Try again in a moment.');
      debugPrint('homeplay pro: $e');
    }
  }

  /// Looks for OwnMedia Pro bought before with this Google account.
  Future<void> restore() async {
    try {
      final before = _bought;
      await _refresh();
      _messages.add(_bought
          ? (before ? 'OwnMedia Pro is yours.' : 'Found it: OwnMedia Pro is yours again.')
          : 'No purchase of OwnMedia Pro on this Google account.');
    } catch (e) {
      _messages.add('Could not reach Google Play. Check the connection.');
    }
  }

  /// Whether the [ProFeature]s may be used with [a]: during the free month, once bought, or when
  /// the server's owner bought (friends invited to it get them too).
  Future<bool> mayUse(Account a) async {
    await _load();
    _publish();
    final s = status.value;
    if (s.bought) unawaited(_keepOn(a));
    if (mayUsePro(enforced: s.enforced, bought: s.bought, trialLeft: s.trialLeft, serverPaid: false)) return true;
    return _paidByOwner(a);
  }

  /// Whether the [ProFeature]s may be used somewhere on this phone: for what belongs to no one
  /// server (the TV, the downloads in the car). [accounts] are the servers; all of them when null.
  Future<bool> mayUseAny([List<Account>? accounts]) async {
    accounts ??= await AccountStore.load();
    await _load();
    _publish();
    final s = status.value;
    if (!s.ended) return true;
    for (final a in accounts) {
      if (await _paidByOwner(a)) return true;
    }
    return false;
  }

  Future<bool> _paidByOwner(Account a) async {
    if (a.kind != ServerKind.jellyfin) return false;
    final prefs = await _load();
    final known = prefs.getStringList(_paidServersKey) ?? const <String>[];
    try {
      final licence = await JellyfinClient(a, await AccountStore.deviceId()).serverLicence();
      final paid = licence != null && isProPurchase(licence);
      final now = {...known};
      paid ? now.add(a.id) : now.remove(a.id);
      await prefs.setStringList(_paidServersKey, now.toList());
      return paid;
    } catch (_) {
      // The server does not answer: as it was last time.
      return known.contains(a.id);
    }
  }

  Future<void> _keepOnAll() async {
    for (final a in await AccountStore.load()) {
      await _keepOn(a);
    }
  }

  // Leaves the purchase on a server of the owner's; other servers refuse it, which is fine.
  Future<void> _keepOn(Account a) async {
    final p = _purchase;
    if (p == null || a.kind != ServerKind.jellyfin || !_keptOn.add(a.id)) return;
    try {
      await JellyfinClient(a, await AccountStore.deviceId()).keepLicence(p);
    } catch (e) {
      _keptOn.remove(a.id);
      debugPrint('homeplay pro: $e');
    }
  }
}
