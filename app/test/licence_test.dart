import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/licence.dart';

// A test key made for these tests (not Google's), and purchases signed with it.
const _key =
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyt+3UmTMjoh9szrZekCiWDRbbo/cJBA2MhCcC15SXiL7HdUGknwVpw+45ifjkN9+cZU+LwD2t87DWZzSR/VseDpzT2BxjO/Fk6qsaF0lHqFKwrezFmyBW6T+gjkfQJ/K9fy2cHNL55ilMLh0Re1YLf7bJ/HnqH6ioGuYoWruFr24HVCrBKrFa5lXvlP69RrwhIGg6o6jLR8PMU4VPvsjX8VP8QWEZXQPZavyeqXO9zoG2iCIu7IfOF9XJdx8h6/YChm1RSfqszdzdmJj/wjP0inAZGMviuAXF2zHIKKgn/xEmG0dhH8a/ssbetfGSD2O+EeoYQ5DeMhvCM60n/UBawIDAQAB';
const _good =
    '{"orderId":"GPA.3301-1234-5678-90123","packageName":"dev.homeplay.homeplay","productId":"ownmedia_pro","purchaseTime":1760900000000,"purchaseState":0,"purchaseToken":"abcdef","quantity":1,"acknowledged":true}';
const _goodSig =
    'G0DJKKBcVs996lxqphbES9Zk8eIR3TEaf9ko76Br4Btj00MQmjixiPays4a4AYm8BGI/aQx4/dEywZrJECNnVAtzVKlfZqpw0/d6ZuqZUusbGeM4OuYGd24xWiIdh9w604IEgmm41ho/0PTDUn6ovgjgGnNvRAROcew0JJgLo+CJ3gzBNfzigbEMVXEf84X06WkY/B0UyE4E5L/8p0GbOMwx6zB267ktyz18/F8M0MqMkPA4xYUmxWOvZYSbO6Obzy93Bsvz9ynb8ypfg+UF5vpx8u00qvYZT7e5eJmWZ6yhQpYgJ8n+f+dhzF1jE+5D8tjyIL+XgboLJMkEi2Asjw==';
const _other =
    '{"orderId":"GPA.3301-1234-5678-90123","packageName":"dev.homeplay.homeplay","productId":"other_thing","purchaseTime":1760900000000,"purchaseState":0,"purchaseToken":"abcdef","quantity":1,"acknowledged":true}';
const _otherSig =
    'ETrE0P3oHnEfp+G0PixvHukXI00+0pOdOQwE+gpNelKa7WzAjvsRNekBpovGoskOl2N8UTUjsV+Z2mqmYttMmDCqbp+cZD4yPoXYbUXbZV+xyH0qJge5Jccu8igcShyeTld3+QyEXMtQWWsYnCECDEYh8WsnGw+/3hfPdCpSeepq3IIiIdNl/uvzTMoTQ9EkFuGRJ/AXoExtkkzzv2g7UIacdIcaXSZ3yFKVL3bUehSe3MG1frnhzM8hMg/9ahX9HipA9sUh14OBnE/x61HMK8EIkQLPAtpK82xvXMiAK/W9UX9tfj1sg0BcNc8WnPdzReDyWfNUVA/VN/iAq6VuWA==';
const _pending =
    '{"orderId":"GPA.3301-1234-5678-90123","packageName":"dev.homeplay.homeplay","productId":"ownmedia_pro","purchaseTime":1760900000000,"purchaseState":4,"purchaseToken":"abcdef","quantity":1,"acknowledged":true}';
const _pendingSig =
    't5m25zPKBBXB1oEQmNQcCOPW1s9w0f4aZZir9M4RBZrHxV98we4GfEI9XKCMMzHgtnVZkcAWcC/GmXJg94ud3CHaOaN6+X6uNNdn1J2Ya5lOqJtCB2gu24dQGlmx6QQSyOUCNk6/DOyAnwJ/tMLUGPbVMTetvkJzYPNaMpSgHkytK5wT/BHgxpnEw8m/P8QfHrGPIsD9IbsVIeJMJ3+ZtGcVUKdqcSRO+18tfd55X2xxQaGD28QWcghesa+s/e9DW4Yt2Pvjxpt1QFmLwZWZdqJuqTj18aKqGX3dkg2KHZaLK1/OpNoNnTqH8OwvPitjF0QVJAqzAVvR2oBbNXW6yw==';

void main() {
  group('a purchase left on a server', () {
    test("counts when Google's signature matches and it is OwnMedia Pro, paid", () {
      expect(isProPurchase((data: _good, signature: _goodSig), key: _key), isTrue);
    });

    test('a changed purchase, a signature of something else or a made-up one do not count', () {
      expect(isProPurchase((data: _good.replaceAll('abcdef', 'abcdeg'), signature: _goodSig), key: _key), isFalse);
      expect(isProPurchase((data: _good, signature: _otherSig), key: _key), isFalse);
      expect(isProPurchase((data: _good, signature: 'AAAA'), key: _key), isFalse);
      expect(isProPurchase((data: _good, signature: 'not base64!'), key: _key), isFalse);
    });

    test('another product or a pending payment does not count, even signed', () {
      expect(isProPurchase((data: _other, signature: _otherSig), key: _key), isFalse);
      expect(isProPurchase((data: _pending, signature: _pendingSig), key: _key), isFalse);
    });

    test('without the key from Play Console nothing counts', () {
      expect(isProPurchase((data: _good, signature: _goodSig), key: ''), isFalse);
      expect(isProPurchase((data: _good, signature: _goodSig), key: 'bm90IGEga2V5'), isFalse);
    });
  });

  group('the trial', () {
    final start = DateTime(2026, 10, 1, 12);

    test('is 30 days from the first start', () {
      expect(trialDaysLeft(start, start), 30);
      expect(trialDaysLeft(start, start.add(const Duration(hours: 23))), 30);
      expect(trialDaysLeft(start, start.add(const Duration(days: 1))), 29);
      expect(trialDaysLeft(start, start.add(const Duration(days: 29, hours: 23))), 1);
      expect(trialDaysLeft(start, start.add(const Duration(days: 30))), 0);
      expect(trialDaysLeft(start, start.add(const Duration(days: 400))), 0);
    });

    test('a clock turned back gives no days back', () {
      final later = start.add(const Duration(days: 31));
      expect(trialDaysLeft(start, start.add(const Duration(days: 2)), lastSeen: later), 0);
      expect(trialDaysLeft(start, start.subtract(const Duration(days: 5))), 30);
    });
  });

  test('a server opens during the trial, when bought, when its owner bought, or while it cannot be bought', () {
    expect(mayOpenServer(enforced: true, bought: false, trialLeft: 3, serverPaid: false), isTrue);
    expect(mayOpenServer(enforced: true, bought: true, trialLeft: 0, serverPaid: false), isTrue);
    expect(mayOpenServer(enforced: true, bought: false, trialLeft: 0, serverPaid: true), isTrue);
    expect(mayOpenServer(enforced: false, bought: false, trialLeft: 0, serverPaid: false), isTrue);
    expect(mayOpenServer(enforced: true, bought: false, trialLeft: 0, serverPaid: false), isFalse);
  });
}
