import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/device_name.dart';

void main() {
  test('the maker goes in front of the model unless the model already names it', () {
    expect(modelWithMaker('Google', 'Pixel 10a'), 'Google Pixel 10a');
    expect(modelWithMaker('samsung', 'SM-S911B'), 'samsung SM-S911B');
    expect(modelWithMaker('Xiaomi', 'xiaomi 14T'), 'xiaomi 14T');
    expect(modelWithMaker(' ', 'Pixel 10a'), 'Pixel 10a');
  });
}
