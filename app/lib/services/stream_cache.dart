/// How mpv holds on through a bad connection: what it keeps ahead on disk, how long it waits for
/// the server, and that it reconnects where the download broke off.
///
/// media_kit gives up after 5 s of silence from the server and keeps 32 MB ahead: on a train
/// or in a lift a song stopped or skipped. Here a song is fetched to its end while the
/// connection is good (it lies in the app's cache folder, not in memory), and a broken
/// download picks up again from the byte it reached.
Map<String, String> streamCacheOptions({required bool music}) => {
      // Seconds without an answer before mpv calls the file broken.
      'network-timeout': '30',
      // Ahead: a whole hi-res album track (24-bit/96 kHz FLAC is about 100 MB) for music; video
      // keeps a few minutes, it may be left after the first scene and would waste mobile data.
      // The cache folder is emptied as each file closes.
      'demuxer-max-bytes': '${music ? 160 : 96}MiB',
      // Behind: a jump back replays from the cache instead of the network.
      'demuxer-max-back-bytes': '${music ? 48 : 32}MiB',
      // FFmpeg's HTTP: on a dropped connection or a network error ask again, from the same byte
      // (Range), waiting up to 30 s between tries. Not for streams without Range (a server
      // conversion): a reconnect would restart them from the beginning.
      'stream-lavf-o': 'reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=30',
    };
