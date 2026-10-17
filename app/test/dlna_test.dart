import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/api/discovery.dart';
import 'package:homeplay/api/dlna.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/screens/tv_screen.dart';
import 'package:homeplay/services/tv_cast.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xml/xml.dart';

/// An LG TV's description, cut down: the renderer is a subdevice of the root.
const _lgDescription = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
    <friendlyName>[LG] webOS TV OLED55C3</friendlyName>
    <manufacturer>LG Electronics</manufacturer>
    <modelName>OLED55C3</modelName>
    <deviceList>
      <device>
        <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
        <friendlyName></friendlyName>
        <serviceList>
          <service>
            <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
            <controlURL>/upnp/control/RenderingControl1</controlURL>
          </service>
          <service>
            <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
            <controlURL>/upnp/control/AVTransport1</controlURL>
          </service>
        </serviceList>
      </device>
    </deviceList>
  </device>
</root>''';

class _FakeTv implements TvControl {
  final calls = <String>[];
  List<TvState> states = [TvState.loading, TvState.playing];
  Duration at = Duration.zero;
  Duration? length = const Duration(minutes: 90);
  bool closed = false;

  @override
  Future<void> open(Uri url, String metadata) async => calls.add('open $url');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration to) async {
    calls.add('seek ${formatTvTime(to)}');
    at = to;
  }

  @override
  Future<({Duration? position, Duration? duration})> position() async => (position: at, duration: length);
  @override
  Future<TvState> state() async => states.length > 1 ? states.removeAt(0) : states.first;
  @override
  void close() => closed = true;
}

class _Reports implements PlaybackReporter {
  final log = <String>[];
  @override
  Future<void> started(Duration position) async => log.add('started ${position.inSeconds}');
  @override
  Future<void> progress(Duration position, {required bool paused}) async => log.add('progress ${position.inSeconds}${paused ? ' paused' : ''}');
  @override
  Future<void> stopped(Duration position, {Duration? duration}) async => log.add('stopped ${position.inSeconds}');
}

PlayItem _movie(_Reports reports, {Uri? url, int? convertedTo}) => PlayItem(
      title: 'Tom & Jerry <1940>',
      url: url ?? Uri.parse('http://192.168.1.5:8096/Videos/abc/stream?static=true&ApiKey=k'),
      isVideo: true,
      container: 'mkv',
      reporter: reports,
      convertedTo: convertedTo,
    );

TvCast _cast(_FakeTv tv, PlayItem item) => TvCast(
      tv: tv,
      tvName: 'Living room',
      item: item,
      pollEvery: const Duration(hours: 1),
      waitStep: Duration.zero,
      stoppedGrace: Duration.zero,
    );

void main() {
  test('SSDP answers give their headers; requests are not answers', () {
    final h = parseSsdp('HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLocation: http://192.168.1.20:1527/\r\n'
        'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n');
    expect(h['location'], 'http://192.168.1.20:1527/');
    expect(h['st'], 'urn:schemas-upnp-org:device:MediaRenderer:1');
    expect(parseSsdp('M-SEARCH * HTTP/1.1\r\nST: x\r\n'), isEmpty);
  });

  test('the TV is found in its description, named by the root when the renderer has no name', () {
    final tv = parseDeviceDescription(_lgDescription, Uri.parse('http://192.168.1.20:1527/desc.xml'))!;
    expect(tv.name, '[LG] webOS TV OLED55C3');
    expect(tv.model, 'LG Electronics OLED55C3');
    expect(tv.controlUrl, Uri.parse('http://192.168.1.20:1527/upnp/control/AVTransport1'));

    // URLBase wins over the description's own address; relative links without a slash too.
    final based = _lgDescription
        .replaceFirst('<device>', '<URLBase>http://192.168.1.20:2000/base/</URLBase><device>')
        .replaceFirst('/upnp/control/AVTransport1', 'av/control');
    expect(parseDeviceDescription(based, Uri.parse('http://192.168.1.20:1527/desc.xml'))!.controlUrl,
        Uri.parse('http://192.168.1.20:2000/base/av/control'));

    // A speaker without AVTransport, or not XML at all: no TV.
    expect(parseDeviceDescription(_lgDescription.replaceAll('AVTransport', 'ContentDirectory'), Uri.parse('http://x/')), isNull);
    expect(parseDeviceDescription('<html>', Uri.parse('http://x/')), isNull);
  });

  test('times as AVTransport writes them', () {
    expect(formatTvTime(const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 900)), '1:02:03');
    expect(formatTvTime(const Duration(seconds: 5)), '0:00:05');
    expect(parseTvTime('1:02:03'), const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(parseTvTime('00:00:05.120'), const Duration(seconds: 5, milliseconds: 120));
    expect(parseTvTime('NOT_IMPLEMENTED'), isNull);
    expect(parseTvTime(''), isNull);
    expect(parseTvTime(null), isNull);
    expect(parseTvState('PAUSED_PLAYBACK'), TvState.paused);
    expect(parseTvState('NO_MEDIA_PRESENT'), TvState.noMedia);
    expect(parseTvState('WEIRD'), TvState.unknown);
  });

  test('the TV is told the file type and title, escaped once in the metadata and once in SOAP', () {
    expect(mimeFor('mkv', isVideo: true), 'video/x-matroska');
    expect(mimeFor('MP4', isVideo: true), 'video/mp4');
    expect(mimeFor('flac', isVideo: false), 'audio/flac');
    expect(mimeFor(null, isVideo: false), 'audio/mpeg');

    final url = Uri.parse('http://s:8096/Videos/1/stream?static=true&ApiKey=k');
    final didl = didlLite(title: 'Tom & Jerry <1940>', url: url, mime: 'video/x-matroska', isVideo: true);
    final parsed = XmlDocument.parse(didl);
    expect(parsed.findAllElements('dc:title').single.innerText, 'Tom & Jerry <1940>');
    expect(parsed.findAllElements('res').single.innerText, '$url');
    expect(parsed.findAllElements('res').single.getAttribute('protocolInfo'), startsWith('http-get:*:video/x-matroska:'));
    expect(parsed.findAllElements('upnp:class').single.innerText, 'object.item.videoItem');

    final soap = XmlDocument.parse(soapEnvelope('SetAVTransportURI', {'InstanceID': '0', 'CurrentURIMetaData': didl}));
    final metadata = soap.descendantElements.firstWhere((e) => e.localName == 'CurrentURIMetaData').innerText;
    expect(metadata, didl);
  });

  test('SOAP answers: values, or the error the TV gave', () {
    const ok = '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
        '<u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
        '<Track>1</Track><TrackDuration>1:30:00</TrackDuration><RelTime>0:10:05</RelTime>'
        '</u:GetPositionInfoResponse></s:Body></s:Envelope>';
    expect(parseSoapAnswer(ok, 'GetPositionInfo')['RelTime'], '0:10:05');
    const fault = '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
        '<detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>714</errorCode>'
        '<errorDescription>Illegal MIME-type</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>';
    expect(() => parseSoapAnswer(fault, 'SetAVTransportURI'),
        throwsA(isA<DlnaException>().having((e) => e.message, 'message', contains('714 Illegal MIME-type'))));
  });

  test('a cast opens the file, goes to the resume point and tells the server', () async {
    final tv = _FakeTv(), reports = _Reports();
    final cast = _cast(tv, _movie(reports));
    await cast.start(startAt: const Duration(minutes: 10));
    expect(tv.calls, ['stop', 'open http://192.168.1.5:8096/Videos/abc/stream?static=true&ApiKey=k', 'play', 'seek 0:10:00']);
    expect(cast.error, isNull);
    expect(cast.state, TvState.playing);
    expect(reports.log, ['started 600']);

    tv.at = const Duration(minutes: 11);
    await cast.poll();
    expect(cast.position, const Duration(minutes: 11));
    expect(cast.duration, const Duration(minutes: 90));

    await cast.togglePause();
    expect(tv.calls.last, 'pause');
    expect(cast.state, TvState.paused);
    await cast.seekBy(const Duration(seconds: -10));
    expect(tv.calls.last, 'seek 0:10:50');
    await cast.seekTo(const Duration(hours: 5));
    expect(tv.calls.last, 'seek 1:30:00', reason: 'not past the end');

    await cast.stop();
    expect(tv.calls.last, 'stop');
    expect(reports.log.last, 'stopped 5400');
    cast.dispose();
    expect(reports.log.where((l) => l.startsWith('stopped')), hasLength(1), reason: 'reported once');
    expect(tv.closed, isTrue);
  });

  test('the TV stopping on its own ends the cast and reports the place', () async {
    final tv = _FakeTv(), reports = _Reports();
    final cast = _cast(tv, _movie(reports));
    await cast.start();
    tv.states = [TvState.stopped];
    tv.at = const Duration(minutes: 89);
    await cast.poll();
    expect(cast.ended, isTrue);
    expect(reports.log, ['started 0', 'stopped 5340']);
    cast.dispose();
  });

  test('a TV that stops answering is shown as gone, and back when it answers again', () async {
    final tv = _FlakyTv(), reports = _Reports();
    final cast = _cast(tv, _movie(reports));
    await cast.start();
    tv.down = true;
    for (var i = 0; i < TvCast.missedToLost - 1; i++) {
      await cast.poll();
    }
    expect(cast.error, isNull, reason: 'one slow answer is not a lost TV');
    await cast.poll();
    expect(cast.error, TvCast.lostMessage);
    expect(cast.ended, isFalse);
    tv.down = false;
    await cast.poll();
    expect(cast.error, isNull);
    expect(cast.state, TvState.playing);
    cast.dispose();
  });

  test('a file the TV cannot open is an error, and nothing is reported', () async {
    final tv = _FakeTv()..states = [TvState.stopped];
    final reports = _Reports();
    final cast = _cast(tv, _movie(reports));
    await cast.start();
    expect(cast.error, contains('192.168.1.5'));
    expect(cast.ended, isTrue);
    cast.dispose();
    expect(reports.log, isEmpty);
  });

  test('downloads and converted streams do not go to a TV', () {
    final reports = _Reports();
    expect(canPlayOnTv(_movie(reports)), isTrue);
    expect(canPlayOnTv(_movie(reports, url: Uri.file('/data/movie.mkv'))), isFalse);
    expect(canPlayOnTv(_movie(reports, convertedTo: 4000000)), isFalse);
  });

  testWidgets('the TV list: searching, found TVs, and what to check when there is none', (tester) async {
    var answer = <TvDevice>[];
    TvDevice? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await pickTv(context, search: () async => answer),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No TV found'), findsOneWidget);

    answer = [
      TvDevice(
        name: '[LG] webOS TV',
        model: 'LG Electronics OLED55C3',
        controlUrl: Uri.parse('http://192.168.1.20:1527/av'),
        location: Uri.parse('http://192.168.1.20:1527/'),
      ),
    ];
    await tester.tap(find.text('Search again'));
    await tester.pumpAndSettle();
    expect(find.text('LG Electronics OLED55C3'), findsOneWidget);
    await tester.tap(find.text('[LG] webOS TV'));
    await tester.pumpAndSettle();
    expect(picked?.name, '[LG] webOS TV');
  });

  testWidgets('the remote: plays, pauses and stops the TV', (tester) async {
    final tv = _FakeTv(), reports = _Reports();
    final cast = _cast(tv, _movie(reports));
    await tester.pumpWidget(MaterialApp(home: TvRemoteScreen(cast: cast)));
    await tester.pumpAndSettle();
    expect(find.text('On Living room'), findsOneWidget);
    expect(find.text('Playing on the TV'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Paused on the TV'), findsOneWidget);
    await tester.tap(find.text('Stop on TV'));
    await tester.pumpAndSettle();
    expect(tv.calls.last, 'stop');
    expect(reports.log.last, startsWith('stopped'));
    expect(tester.takeException(), isNull);
  });

  test('home addresses a TV can reach, and links moved to them', () {
    for (final h in ['192.168.1.10', '10.0.0.5', '172.20.1.1', 'nas.local', '169.254.3.4']) {
      expect(isHomeHost(h), isTrue, reason: h);
    }
    for (final h in ['100.121.58.29', 'nas-3d.tailc91480.ts.net', '172.32.0.1', '8.8.8.8', 'localhost', '192.168.1']) {
      expect(isHomeHost(h), isFalse, reason: h);
    }
    final url = Uri.parse('https://nas.ts.net/Videos/1/stream?static=true&ApiKey=k');
    expect(rebaseUrl(url, 'https://nas.ts.net', 'http://192.168.1.10:8096/'),
        Uri.parse('http://192.168.1.10:8096/Videos/1/stream?static=true&ApiKey=k'));
    expect(rebaseUrl(Uri.parse('https://nas.ts.net.evil/x'), 'https://nas.ts.net', 'http://h'), Uri.parse('https://nas.ts.net.evil/x'));
  });

  group('the TV gets the server at its home address', () {
    const remote = Account(
        id: 'a', kind: ServerKind.jellyfin, baseUrl: 'https://nas.ts.net', username: 'u', serverName: 'NAS', token: 't', userId: 'u1');
    final movie = JellyfinItem(const {'Id': 'm1', 'Name': 'Movie', 'Type': 'Movie', 'MediaType': 'Video', 'Container': 'mkv'});

    JellyfinClient client({
      String? local = 'http://192.168.1.10:8096',
      String homeId = 'S1',
      bool homeAnswers = true,
      List<DiscoveredServer> onWifi = const [],
    }) =>
        JellyfinClient(remote, 'dev', discover: () async => onWifi, client: MockClient((r) async {
          if (r.url.host == 'nas.ts.net') {
            return http.Response('{"Id":"S1","ServerName":"NAS"${local == null ? '' : ',"LocalAddress":"$local"'}}', 200);
          }
          if (!homeAnswers) throw const SocketExceptionLike();
          return http.Response('{"Id":"$homeId"}', 200);
        }));

    test('when the phone reaches the same server there', () async {
      final url = await client().toPlayItem(movie).tvUrl!();
      expect(url.toString(), startsWith('http://192.168.1.10:8096/Videos/m1/stream'));
      expect(url.queryParameters['ApiKey'], 't');
    });

    test('otherwise the address the phone uses', () async {
      for (final c in [
        client(homeAnswers: false), // the phone is away from home
        client(homeId: 'OTHER'), // another server answers at that address
        client(local: 'http://100.121.58.29:8096'), // a Tailscale address
        client(local: null),
      ]) {
        expect((await c.toPlayItem(movie).tvUrl!()).host, 'nas.ts.net');
      }
    });

    test('the Wi-Fi search finds it when the server names a Tailscale address for itself', () async {
      final c = client(local: 'http://100.121.58.29:8096', onWifi: const [
        DiscoveredServer(name: 'Other', address: 'http://192.168.1.20:8096', id: 'OTHER'),
        DiscoveredServer(name: 'NAS', address: 'http://192.168.1.10:8096', id: 'S1'),
      ]);
      expect((await c.toPlayItem(movie).tvUrl!()).host, '192.168.1.10');
    });

    test('a server added by its home address is left as it is', () async {
      const home = Account(
          id: 'h', kind: ServerKind.jellyfin, baseUrl: 'http://192.168.1.10:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'u1');
      var asked = 0;
      final c = JellyfinClient(home, 'dev', client: MockClient((r) async {
        asked++;
        return http.Response('{}', 200);
      }));
      expect((await c.toPlayItem(movie).tvUrl!()).host, '192.168.1.10');
      expect(asked, 0);
    });
  });
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}

class _FlakyTv extends _FakeTv {
  bool down = false;

  @override
  Future<TvState> state() => down ? Future.error(TimeoutException('no answer')) : super.state();
}
