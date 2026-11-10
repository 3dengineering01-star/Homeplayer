import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/library_order.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<String> _arrange(LibraryOrder o, List<String> server, {bool withHidden = false}) =>
    o.arrange(server, (id) => id, withHidden: withHidden);

void main() {
  const server = ['movies', 'shows', 'music', 'photos'];

  test('nothing chosen: the server order', () {
    expect(_arrange(const LibraryOrder(), server), server);
    expect(const LibraryOrder().isDefault, isTrue);
  });

  test('the chosen order, hidden ones left out', () {
    const o = LibraryOrder(order: ['music', 'movies', 'shows', 'photos'], hidden: {'photos'});
    expect(_arrange(o, server), ['music', 'movies', 'shows']);
    expect(_arrange(o, server, withHidden: true), ['music', 'movies', 'shows', 'photos']);
  });

  test('a library new on the server comes at the end; a removed one is skipped', () {
    const o = LibraryOrder(order: ['music', 'gone', 'movies']);
    expect(_arrange(o, [...server, 'books']), ['music', 'movies', 'shows', 'photos', 'books']);
  });

  test('kept as text and read back; damaged text is the default', () {
    const o = LibraryOrder(order: ['b', 'a'], hidden: {'c'});
    final back = LibraryOrder.decode(o.encode());
    expect(back.order, ['b', 'a']);
    expect(back.hidden, {'c'});
    expect(LibraryOrder.decode(null).isDefault, isTrue);
    expect(LibraryOrder.decode('{oops').isDefault, isTrue);
    expect(LibraryOrder.decode('{"order":[1,"x"],"hidden":"y"}').order, ['x']);
  });

  test('per server, and forgotten with it', () async {
    SharedPreferences.setMockInitialValues({});
    await const LibraryOrder(order: ['x'], hidden: {'y'}).save('one');
    expect((await LibraryOrder.load('one')).hidden, {'y'});
    expect((await LibraryOrder.load('two')).isDefault, isTrue);
    await LibraryOrder.forget('one');
    expect((await LibraryOrder.load('one')).isDefault, isTrue);
    // Back to the default: nothing kept.
    await const LibraryOrder(order: ['x']).save('one');
    await const LibraryOrder().save('one');
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });
}
