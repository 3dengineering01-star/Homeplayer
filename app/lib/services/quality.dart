import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How video reaches the phone: the original file, a cap the app measures before playing,
/// or a fixed cap in bit/s. Above the cap the server converts the video.
class VideoQuality {
  const VideoQuality._(this._value);

  /// For the menu: a fixed cap.
  const VideoQuality.capped(int bitsPerSecond) : _value = bitsPerSecond;

  static const original = VideoQuality._(0);
  static const auto = VideoQuality._(-1);

  static const choices = [
    original,
    auto,
    VideoQuality.capped(20000000),
    VideoQuality.capped(10000000),
    VideoQuality.capped(6000000),
    VideoQuality.capped(4000000),
    VideoQuality.capped(2000000),
    VideoQuality.capped(1000000),
  ];

  final int _value;

  bool get isOriginal => _value == 0;
  bool get isAuto => _value < 0;

  /// The fixed cap; null for [original] and [auto].
  int? get cap => _value > 0 ? _value : null;

  String get label => isOriginal
      ? 'Original'
      : isAuto
          ? 'Auto'
          : bitrateLabel(_value);

  String get description => isOriginal
      ? 'The file as it is, best picture'
      : isAuto
          ? 'Measures the connection and converts only when the file would not fit'
          : 'The server converts larger files to this';

  int toPref() => _value;

  static VideoQuality fromPref(int? v) => v == null || v == 0
      ? original
      : v < 0
          ? auto
          : VideoQuality.capped(v);

  @override
  bool operator ==(Object other) => other is VideoQuality && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}

/// "4 Mbit/s", "1.5 Mbit/s".
String bitrateLabel(int bitsPerSecond) {
  final m = bitsPerSecond / 1e6;
  return '${m == m.roundToDouble() ? m.round() : m.toStringAsFixed(1)} Mbit/s';
}

/// Taken when [VideoQuality.auto] cannot measure the connection.
const fallbackCap = 4000000;

/// The bitrate cap for [quality]: null means play the original. [measured] is the speed
/// to the server in bit/s; video gets 70% of it, leaving room for audio and dips.
int? capFor(VideoQuality quality, {double? measured}) {
  if (quality.isOriginal) return null;
  if (!quality.isAuto) return quality.cap;
  if (measured == null || measured <= 0) return fallbackCap;
  return (measured * 0.7).clamp(1000000, 120000000).round();
}

/// Whether a file of [sourceBitrate] must be converted under [cap]. An unknown bitrate
/// plays as it is: converting blindly would cost more than it saves.
bool needsConversion(int? sourceBitrate, int? cap) =>
    cap != null && sourceBitrate != null && sourceBitrate > cap;

/// The user's choice for Wi-Fi and for mobile data.
class QualitySettings {
  static const _wifiKey = 'quality_wifi';
  static const _mobileKey = 'quality_mobile';

  static Future<({VideoQuality wifi, VideoQuality mobile})> load() async {
    final p = await SharedPreferences.getInstance();
    return (
      wifi: VideoQuality.fromPref(p.getInt(_wifiKey)),
      // Mobile data is often slow or metered, so it measures unless told otherwise.
      mobile: p.containsKey(_mobileKey) ? VideoQuality.fromPref(p.getInt(_mobileKey)) : VideoQuality.auto,
    );
  }

  static Future<void> save({VideoQuality? wifi, VideoQuality? mobile}) async {
    final p = await SharedPreferences.getInstance();
    if (wifi != null) await p.setInt(_wifiKey, wifi.toPref());
    if (mobile != null) await p.setInt(_mobileKey, mobile.toPref());
  }

  /// The setting for the network the phone is on now. Ethernet counts as Wi-Fi.
  static Future<VideoQuality> current() async {
    final s = await load();
    List<ConnectivityResult> net;
    try {
      net = await Connectivity().checkConnectivity();
    } catch (_) {
      return s.wifi;
    }
    final local = net.contains(ConnectivityResult.wifi) || net.contains(ConnectivityResult.ethernet);
    return !local && net.contains(ConnectivityResult.mobile) ? s.mobile : s.wifi;
  }
}
