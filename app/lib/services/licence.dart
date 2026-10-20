import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// OwnMedia Pro: a month to try, then one purchase on Google Play. Friends who joined a server by
/// invite watch free when the owner of that server bought it: the owner's app leaves the signed
/// purchase on the server (Homeplay Backup plugin), and the friend's app checks Google's signature.
/// Pure rules here; the store and the servers are in pro.dart.

/// The purchase in Google Play Console (Monetize → Products → In-app products).
const proProductId = 'ownmedia_pro';

/// The app's package, as Google writes it in every purchase.
const appPackage = 'dev.homeplay.homeplay';

/// How long the app is free.
const trialDays = 30;

/// Google Play's public key for this app: Play Console → Monetize → Monetization setup →
/// Licensing. It is public; Google signs every purchase with the matching private key.
/// Empty until the app is in Play Console: then no purchase on a server counts.
const googlePlayKey = '';

/// A purchase as Google Play gives it: its JSON and Google's signature of that text.
typedef SignedPurchase = ({String data, String signature});

/// Whole days of the trial left on [now], when it started on [start]: 30 on the first day,
/// 0 once it is over. A clock turned back does not give days back: [lastSeen] is the latest time
/// the app saw.
int trialDaysLeft(DateTime start, DateTime now, {DateTime? lastSeen}) {
  final at = lastSeen != null && lastSeen.isAfter(now) ? lastSeen : now;
  final used = at.difference(start);
  if (used.isNegative) return trialDays;
  final left = trialDays - used.inDays;
  return left.clamp(0, trialDays);
}

/// Whether a server may be opened. [enforced] is false while the purchase cannot be made on this
/// phone (no Google Play, or the product is not in the store yet): nobody is locked out of
/// something they cannot buy.
bool mayOpenServer({
  required bool enforced,
  required bool bought,
  required int trialLeft,
  required bool serverPaid,
}) =>
    !enforced || bought || trialLeft > 0 || serverPaid;

/// Whether [p] is a real purchase of OwnMedia Pro: signed by Google with [key] (base64 of the
/// key Play Console shows), for this app and this product, and paid (not pending or refunded).
bool isProPurchase(SignedPurchase p, {String key = googlePlayKey}) {
  if (key.isEmpty || p.data.isEmpty || p.signature.isEmpty) return false;
  try {
    return verifyRsaSha1(utf8.encode(p.data), base64.decode(p.signature), base64.decode(key)) && isProData(p.data);
  } catch (_) {
    return false;
  }
}

/// Whether the purchase JSON [data] is OwnMedia Pro for this app, paid. Says nothing about who
/// wrote it: see [isProPurchase].
bool isProData(String data) {
  try {
    final j = jsonDecode(data);
    return j is Map && j['packageName'] == appPackage && j['productId'] == proProductId && (j['purchaseState'] ?? 0) == 0;
  } catch (_) {
    return false;
  }
}

/// RSA signature check as Google Play signs purchases (SHA1withRSA, PKCS #1 v1.5).
/// [publicKey] is the key in X.509 form (DER), as Play Console gives it in base64.
bool verifyRsaSha1(List<int> message, List<int> signature, List<int> publicKey) {
  final key = _rsaKey(Uint8List.fromList(publicKey));
  if (key == null) return false;
  final k = (key.n.bitLength + 7) ~/ 8;
  if (signature.length != k) return false;
  final s = _toInt(signature);
  if (s >= key.n) return false;
  final em = _toBytes(s.modPow(key.e, key.n), k);
  // 00 01 FF..FF 00, then the SHA-1 DigestInfo and the hash.
  const digestInfo = [0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14];
  final hash = sha1.convert(message).bytes;
  final tail = [0x00, ...digestInfo, ...hash];
  final pad = k - 2 - tail.length;
  if (pad < 8 || em[0] != 0x00 || em[1] != 0x01) return false;
  for (var i = 0; i < pad; i++) {
    if (em[2 + i] != 0xff) return false;
  }
  var same = true;
  for (var i = 0; i < tail.length; i++) {
    same &= em[2 + pad + i] == tail[i];
  }
  return same;
}

// The modulus and exponent from SubjectPublicKeyInfo:
// SEQUENCE { SEQUENCE { OID, NULL }, BIT STRING { 00, SEQUENCE { INTEGER n, INTEGER e } } }.
({BigInt n, BigInt e})? _rsaKey(Uint8List der) {
  try {
    final outer = _Der(der).read(0x30);
    final info = _Der(outer);
    info.read(0x30); // the algorithm
    final bits = info.read(0x03);
    if (bits.isEmpty || bits[0] != 0) return null;
    final rsa = _Der(_Der(Uint8List.sublistView(bits, 1)).read(0x30));
    final n = _toInt(rsa.read(0x02));
    final e = _toInt(rsa.read(0x02));
    if (n <= BigInt.zero || e <= BigInt.zero) return null;
    return (n: n, e: e);
  } catch (_) {
    return null;
  }
}

/// Reads DER items one after another.
class _Der {
  _Der(this.bytes);
  final Uint8List bytes;
  int _at = 0;

  /// The contents of the next item, which must have [tag].
  Uint8List read(int tag) {
    if (bytes[_at++] != tag) throw const FormatException('unexpected DER tag');
    var length = bytes[_at++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4) throw const FormatException('bad DER length');
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[_at++];
      }
    }
    if (_at + length > bytes.length) throw const FormatException('DER item too long');
    final value = Uint8List.sublistView(bytes, _at, _at + length);
    _at += length;
    return value;
  }
}

BigInt _toInt(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

List<int> _toBytes(BigInt v, int length) {
  final out = List<int>.filled(length, 0);
  var x = v;
  for (var i = length - 1; i >= 0 && x > BigInt.zero; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x >>= 8;
  }
  return out;
}
