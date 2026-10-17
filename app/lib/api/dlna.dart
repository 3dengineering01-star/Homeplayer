import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// A TV or other player on the home network that plays a link it is given (a UPnP/DLNA
/// "media renderer": LG, Samsung, Sony, Philips TVs and many receivers have one built in).
class TvDevice {
  const TvDevice({required this.name, required this.model, required this.controlUrl, required this.location});

  final String name;

  /// Maker and model, e.g. "LG Electronics OLED55C3"; may be empty.
  final String model;

  /// Where AVTransport commands go.
  final Uri controlUrl;

  /// The device description, which identifies the device.
  final Uri location;
}

class DlnaException implements Exception {
  DlnaException(this.message);
  final String message;

  @override
  String toString() => message;
}

const avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';

/// What a TV is doing, as AVTransport names it.
enum TvState { playing, paused, stopped, loading, noMedia, unknown }

TvState parseTvState(String? s) => switch (s) {
      'PLAYING' => TvState.playing,
      'PAUSED_PLAYBACK' || 'PAUSED_RECORDING' => TvState.paused,
      'STOPPED' => TvState.stopped,
      'TRANSITIONING' => TvState.loading,
      'NO_MEDIA_PRESENT' => TvState.noMedia,
      _ => TvState.unknown,
    };

/// Headers of an SSDP answer, names in lower case; empty when it is not an HTTP-like answer.
Map<String, String> parseSsdp(String message) {
  final lines = message.split(RegExp(r'\r?\n'));
  if (lines.isEmpty || !lines.first.toUpperCase().startsWith('HTTP/')) return const {};
  return {
    for (final line in lines.skip(1))
      if (line.contains(':')) line.substring(0, line.indexOf(':')).trim().toLowerCase(): line.substring(line.indexOf(':') + 1).trim(),
  };
}

/// The TV in a device description fetched from [location]: the (sub)device with an AVTransport
/// service, named by itself or, failing that, by the root device. Null when there is none.
TvDevice? parseDeviceDescription(String body, Uri location) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } catch (_) {
    return null;
  }
  String? text(XmlElement e, String name) {
    for (final c in e.childElements) {
      if (c.localName == name) return c.innerText.trim();
    }
    return null;
  }

  final base = doc.descendantElements.where((e) => e.localName == 'URLBase').map((e) => e.innerText.trim()).firstOrNull;
  final baseUri = base != null && base.isNotEmpty ? Uri.tryParse(base) ?? location : location;
  final devices = doc.descendantElements.where((e) => e.localName == 'device').toList();
  for (final device in devices) {
    final services = device.childElements
        .where((e) => e.localName == 'serviceList')
        .expand((l) => l.childElements.where((e) => e.localName == 'service'));
    for (final service in services) {
      final type = text(service, 'serviceType') ?? '';
      final control = text(service, 'controlURL');
      if (!type.contains(':service:AVTransport:') || control == null || control.isEmpty) continue;
      final named = text(device, 'friendlyName')?.isNotEmpty ?? false ? device : devices.first;
      final model = [text(named, 'manufacturer'), text(named, 'modelName')].whereType<String>().where((s) => s.isNotEmpty);
      return TvDevice(
        name: text(named, 'friendlyName') ?? location.host,
        model: model.join(' '),
        controlUrl: baseUri.resolve(control),
        location: location,
      );
    }
  }
  return null;
}

/// "1:02:03" as AVTransport wants it for Seek.
String formatTvTime(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// "1:02:03", "0:00:05.120" or "01:02:03"; null for "NOT_IMPLEMENTED", an empty or a bad value.
Duration? parseTvTime(String? s) {
  final m = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d+))?$').firstMatch(s?.trim() ?? '');
  if (m == null) return null;
  final fraction = m.group(4);
  return Duration(
    hours: int.parse(m.group(1)!),
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
    milliseconds: fraction == null ? 0 : (double.parse('0.$fraction') * 1000).round(),
  );
}

/// The type a TV is told the file has, from the server's container name.
String mimeFor(String? container, {required bool isVideo}) => switch (container?.toLowerCase()) {
      'mkv' || 'matroska' => 'video/x-matroska',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => isVideo ? 'video/webm' : 'audio/webm',
      'avi' => 'video/x-msvideo',
      'ts' || 'mpegts' || 'm2ts' => 'video/mp2t',
      'mpg' || 'mpeg' => 'video/mpeg',
      'wmv' || 'asf' => 'video/x-ms-wmv',
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      'm4a' || 'aac' => 'audio/mp4',
      'ogg' || 'oga' => 'audio/ogg',
      'opus' => 'audio/ogg',
      'wav' => 'audio/wav',
      _ => isVideo ? 'video/mp4' : 'audio/mpeg',
    };

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// What the TV shows about the file: title, kind and a link with its type. LG and Samsung refuse
/// a link without it. OP=01: the TV may seek with byte ranges, which the server allows.
String didlLite({required String title, required Uri url, required String mime, required bool isVideo, Uri? artwork}) {
  final kind = isVideo ? 'object.item.videoItem' : 'object.item.audioItem.musicTrack';
  final protocol = 'http-get:*:$mime:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000';
  return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="0" parentID="-1" restricted="1">'
      '<dc:title>${_escape(title)}</dc:title>'
      '<upnp:class>$kind</upnp:class>'
      '${artwork == null ? '' : '<upnp:albumArtURI>${_escape(artwork.toString())}</upnp:albumArtURI>'}'
      '<res protocolInfo="$protocol">${_escape(url.toString())}</res>'
      '</item></DIDL-Lite>';
}

/// A SOAP call of [action] with [args] in their order; values are escaped here.
String soapEnvelope(String action, Map<String, String> args, {String service = avTransport}) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
    '<s:Body><u:$action xmlns:u="$service">'
    '${args.entries.map((e) => '<${e.key}>${_escape(e.value)}</${e.key}>').join()}'
    '</u:$action></s:Body></s:Envelope>';

/// The values of a SOAP answer, or the error the device gave.
Map<String, String> parseSoapAnswer(String body, String action) {
  final doc = XmlDocument.parse(body);
  final fault = doc.descendantElements.where((e) => e.localName == 'UPnPError').firstOrNull;
  if (fault != null) {
    String part(String name) => fault.descendantElements.where((e) => e.localName == name).map((e) => e.innerText).firstOrNull ?? '';
    throw DlnaException('The TV refused $action (${part('errorCode')} ${part('errorDescription')})'.replaceAll(' )', ')'));
  }
  final answer = doc.descendantElements.where((e) => e.localName == '${action}Response').firstOrNull;
  if (answer == null) throw DlnaException('The TV gave no answer to $action');
  return {for (final c in answer.childElements) c.localName: c.innerText};
}

/// Whether a TV at home can reach [host] directly: a private address of the home network or a
/// ".local" name. Tailscale's addresses (100.64.0.0/10) and internet names are not.
bool isHomeHost(String host) {
  if (host.endsWith('.local')) return true;
  final p = host.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.any((n) => n == null || n < 0 || n > 255)) return false;
  final a = p[0]!, b = p[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
}

/// [url] under [from] moved to the same place under [to], e.g. a stream link from the server's
/// internet address to its home address; [url] itself when it is not under [from].
Uri rebaseUrl(Uri url, String from, String to) {
  String trim(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;
  final f = trim(from), t = trim(to), u = '$url';
  return u.startsWith(f) && (u.length == f.length || '/?#'.contains(u[f.length])) ? Uri.parse('$t${u.substring(f.length)}') : url;
}

/// What the app asks of a TV; [DlnaTv] over the network, a fake in tests.
abstract interface class TvControl {
  Future<void> open(Uri url, String metadata);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration to);
  Future<({Duration? position, Duration? duration})> position();
  Future<TvState> state();
  void close();
}

/// Commands to one TV.
class DlnaTv implements TvControl {
  DlnaTv(this.device, {http.Client? client}) : _http = client ?? http.Client();

  final TvDevice device;
  final http.Client _http;

  Future<Map<String, String>> _call(String action, [Map<String, String> args = const {}]) async {
    final res = await _http
        .post(
          device.controlUrl,
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPACTION': '"$avTransport#$action"',
          },
          body: utf8.encode(soapEnvelope(action, {'InstanceID': '0', ...args})),
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200 && res.statusCode != 500) {
      throw DlnaException('The TV answered ${res.statusCode} to $action');
    }
    return parseSoapAnswer(utf8.decode(res.bodyBytes, allowMalformed: true), action);
  }

  @override
  Future<void> open(Uri url, String metadata) => _call('SetAVTransportURI', {'CurrentURI': '$url', 'CurrentURIMetaData': metadata});

  @override
  Future<void> play() => _call('Play', {'Speed': '1'});

  @override
  Future<void> pause() => _call('Pause');

  @override
  Future<void> stop() => _call('Stop');

  @override
  Future<void> seek(Duration to) => _call('Seek', {'Unit': 'REL_TIME', 'Target': formatTvTime(to)});

  @override
  Future<({Duration? position, Duration? duration})> position() async {
    final a = await _call('GetPositionInfo');
    return (position: parseTvTime(a['RelTime']), duration: parseTvTime(a['TrackDuration']));
  }

  @override
  Future<TvState> state() async => parseTvState((await _call('GetTransportInfo'))['CurrentTransportState']);

  @override
  void close() => _http.close();
}

/// TVs on the home network that can play a link: asked over SSDP, then each one's description.
Future<List<TvDevice>> discoverTvs({Duration timeout = const Duration(seconds: 3), http.Client? client}) async {
  final locations = <Uri>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final s = socket;
    s.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = s.receive();
      if (d == null) return;
      final location = Uri.tryParse(parseSsdp(utf8.decode(d.data, allowMalformed: true))['location'] ?? '');
      if (location != null && location.hasScheme && location.host.isNotEmpty) locations.add(location);
    });
    final group = InternetAddress('239.255.255.250');
    for (final target in ['urn:schemas-upnp-org:device:MediaRenderer:1', avTransport]) {
      final search = 'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: $target\r\n\r\n';
      s.send(utf8.encode(search), group, 1900);
    }
    await Future.delayed(timeout);
  } catch (e) {
    debugPrint('homeplay TV search failed: $e');
  } finally {
    socket?.close();
  }

  final web = client ?? http.Client();
  try {
    final found = await Future.wait(locations.map((l) async {
      try {
        final res = await web.get(l).timeout(const Duration(seconds: 4));
        return res.statusCode == 200 ? parseDeviceDescription(utf8.decode(res.bodyBytes, allowMalformed: true), l) : null;
      } catch (e) {
        debugPrint('homeplay TV description from ${l.host} failed: $e');
        return null;
      }
    }));
    // One entry per TV even when it answers both searches with different description links.
    final byControl = <String, TvDevice>{};
    for (final tv in found.whereType<TvDevice>()) {
      byControl.putIfAbsent('${tv.controlUrl}', () => tv);
    }
    return byControl.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  } finally {
    if (client == null) web.close();
  }
}
