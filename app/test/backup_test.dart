import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/backup.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/services/backup_ledger.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The plugin's Upload endpoint: keeps the bytes, answers with its offset, 409 on a wrong one.
class FakeServer {
  final received = <int>[];
  final requests = <Uri>[];
  int? failAt; // throw once when a chunk starts here, like a dropped connection

  Future<http.Response> handle(http.Request r) async {
    requests.add(r.url);
    if (r.url.path.endsWith('/Info')) return http.Response('{"Version":"1.0.0.0","Configured":true}', 200);
    final q = r.url.queryParameters;
    final size = int.parse(q['size']!), offset = int.parse(q['offset']!);
    if (offset == failAt) {
      failAt = null;
      received.addAll(r.bodyBytes); // the server got it, the phone never heard back
      throw http.ClientException('Connection reset');
    }
    if (offset != received.length) {
      return http.Response(jsonEncode({'Id': q['id'], 'Done': false, 'Offset': received.length}), 409);
    }
    received.addAll(r.bodyBytes.take(size - offset));
    final done = received.length >= size;
    return http.Response(jsonEncode({'Id': q['id'], 'Done': done, 'Offset': done ? 0 : received.length}), 200);
  }
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('homeplay'));
  tearDown(() => tmp.delete(recursive: true));

  final client = JellyfinClient(
    const Account(id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'x'),
    'dev',
  );

  Future<File> file(int size) async {
    final f = File('${tmp.path}/v.mp4');
    await f.writeAsBytes(List.generate(size, (i) => i % 251));
    return f;
  }

  Future<void> send(BackupApi api, File f, {int offset = 0}) => api.upload(
        device: 'Pixel 10a',
        id: '42',
        name: 'PXL_1.mp4',
        takenAt: DateTime.utc(2026, 10, 6),
        file: f,
        offset: offset,
      );

  test('a big file goes in chunks and arrives whole', () async {
    final server = FakeServer();
    final f = await file(BackupApi.chunkSize * 2 + 10);
    await send(BackupApi(client, client: MockClient(server.handle)), f);
    expect(server.received, await f.readAsBytes());
    expect(server.requests.map((u) => u.queryParameters['offset']), ['0', '${BackupApi.chunkSize}', '${BackupApi.chunkSize * 2}']);
    expect(server.requests.first.queryParameters, containsPair('takenAt', '2026-10-06T00:00:00.000Z'));
  });

  test('after a lost answer the server says where to go on, and nothing is sent twice', () async {
    final server = FakeServer()..failAt = BackupApi.chunkSize;
    final f = await file(BackupApi.chunkSize * 2 + 10);
    final api = BackupApi(client, client: MockClient(server.handle));
    await expectLater(send(api, f), throwsA(isA<http.ClientException>()));
    // The next run starts from what it last knew; the server corrects it with 409.
    await send(api, f, offset: BackupApi.chunkSize);
    expect(server.received, await f.readAsBytes());
  });

  test('an empty file is one request', () async {
    final server = FakeServer();
    await send(BackupApi(client, client: MockClient(server.handle)), await file(0));
    expect(server.requests, hasLength(1));
  });

  test('a missing plugin, a server without a folder, and an expired session', () async {
    BackupApi answering(int code, [String body = '']) =>
        BackupApi(client, client: MockClient((_) async => http.Response(body, code)));
    expect(await answering(404).status(), BackupServerStatus.missing);
    expect(await answering(200, '{"Version":"1","Configured":false}').status(), BackupServerStatus.notConfigured);
    expect(await answering(200, '{"Version":"1","Configured":true}').status(), BackupServerStatus.ready);
    await expectLater(answering(401).status(), throwsA(isA<ApiException>()));
  });

  test('check reads the plugin answer', () async {
    final api = BackupApi(client, client: MockClient((r) async {
      expect(jsonDecode(r.body), {'Device': 'Pixel 10a', 'Ids': ['1', '2']});
      return http.Response('[{"Id":"1","Done":true,"Offset":0},{"Id":"2","Done":false,"Offset":512}]', 200);
    }));
    final known = await api.check('Pixel 10a', ['1', '2']);
    expect(known['1']!.done, isTrue);
    expect((known['2']!.done, known['2']!.offset), (false, 512));
  });

  test('the ledger remembers sent photos across runs', () async {
    final f = File('${tmp.path}/sent.txt');
    final ledger = await BackupLedger.open(f);
    await ledger.addAll(['1', '2']);
    await ledger.addAll(['2', '3']);
    final again = await BackupLedger.open(f);
    expect(again.length, 3);
    expect(again.contains('3'), isTrue);
    await again.clear();
    expect((await BackupLedger.open(f)).length, 0);
  });
}
