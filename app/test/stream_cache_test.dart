import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/stream_cache.dart';

void main() {
  test('a bad connection: longer wait, a whole song ahead, reconnect from the same byte', () {
    final music = streamCacheOptions(music: true);
    expect(int.parse(music['network-timeout']!), greaterThanOrEqualTo(30));
    expect(music['demuxer-max-bytes'], '160MiB');
    expect(music['stream-lavf-o'], contains('reconnect=1'));
    // Never restart a stream without Range from its start.
    expect(music['stream-lavf-o'], isNot(contains('reconnect_streamed')));
    // Video keeps less ahead: it may be left after a minute.
    expect(streamCacheOptions(music: false)['demuxer-max-bytes'], '96MiB');
  });
}
