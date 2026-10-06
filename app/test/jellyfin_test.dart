import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';

MediaVersion version(String name, {int? width, int? height, String? codec, String? range, int? size}) =>
    MediaVersion({
      'Id': name,
      'Name': name,
      'Size': size,
      'MediaStreams': [
        {'Type': 'Audio', 'Codec': 'truehd'},
        if (width != null) {'Type': 'Video', 'Width': width, 'Height': height, 'Codec': codec, 'VideoRangeType': range},
      ],
    });

void main() {
  test('versions read like a menu', () {
    expect(version('Director\'s Cut', width: 3840, height: 2160, codec: 'hevc', range: 'DOVIWithHDR10', size: 62488082432).details,
        '4K · HEVC · Dolby Vision · 58.2 GB');
    expect(version('Theatrical', width: 1920, height: 800, codec: 'h264', range: 'SDR', size: 891289600).details,
        '1080p · H.264 · 850 MB');
    expect(version('DVD', width: 720, height: 576, codec: 'mpeg2video').details, '576p · MPEG-2');
    expect(version('Extended', width: 3840, height: 2160, codec: 'hevc', range: 'HDR10Plus').details, '4K · HEVC · HDR10+');
  });

  test('details skip what the name already says, and survive missing streams', () {
    expect(version('1080p', width: 1920, height: 1080, codec: 'hevc').details, 'HEVC');
    expect(version('4K HDR10', width: 3840, height: 2160, codec: 'hevc', range: 'HDR10').details, 'HEVC');
    expect(version('Old rip', size: 734003200).details, '700 MB');
    expect(MediaVersion({'Id': 'x'}).details, '');
  });

  test('items without versions count as one', () {
    expect(JellyfinItem({'Id': 'a'}).versionCount, 1);
    expect(JellyfinItem({'Id': 'a', 'MediaSourceCount': 2}).versionCount, 2);
  });
}
