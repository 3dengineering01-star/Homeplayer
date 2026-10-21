import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/widgets/mini_player.dart';

void main() {
  test('a swipe on the mini player: sideways changes the track, up opens the player', () {
    expect(miniSwipe(-120, 10, -300, 0), MiniSwipe.next);
    expect(miniSwipe(120, -10, 300, 0), MiniSwipe.previous);
    // A short quick flick counts, a short slow slide does not.
    expect(miniSwipe(-30, 0, -900, 0), MiniSwipe.next);
    expect(miniSwipe(-30, 0, -100, 0), MiniSwipe.none);
    expect(miniSwipe(5, -80, 0, -200), MiniSwipe.open);
    expect(miniSwipe(0, -20, 0, -900), MiniSwipe.open);
    // Down does nothing: the bar is already at the bottom.
    expect(miniSwipe(0, 80, 0, 900), MiniSwipe.none);
  });
}
