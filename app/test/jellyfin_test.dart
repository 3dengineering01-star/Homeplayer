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

  test('a remembered resolution picks the version without asking', () {
    final versions = [
      version('Remux', width: 3840, height: 2160, codec: 'hevc'),
      version('Web', width: 1920, height: 1036, codec: 'h264'),
      version('Web HEVC', width: 1920, height: 1080, codec: 'hevc'),
    ];
    expect(versions.map((v) => v.resolution), ['4K', '1080p', '1080p']);
    expect(chooseVersion(versions, '1080p')?.id, 'Web'); // the first one, in the server's order
    expect(chooseVersion(versions, '4K')?.id, 'Remux');
    expect(chooseVersion(versions, '720p'), isNull); // nothing like it: ask
    expect(chooseVersion(versions, null), isNull);
    expect(version('Old rip').resolution, isNull);
  });

  test('items without versions count as one', () {
    expect(JellyfinItem({'Id': 'a'}).versionCount, 1);
    expect(JellyfinItem({'Id': 'a', 'MediaSourceCount': 2}).versionCount, 2);
  });
}
