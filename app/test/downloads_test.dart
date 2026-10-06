import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/common.dart';
import 'package:homeplay/services/downloads.dart';

void main() {
  const entry = DownloadEntry(
    id: 'abc123',
    title: 'Episode 1',
    subtitle: 'Show · S1E1',
    group: 'Season 1',
    isVideo: true,
    hasArtwork: true,
    subtitles: [SavedSubtitle(file: 'sub_abc123_0', title: 'External', language: 'rus')],
    state: DownloadState.done,
    progress: 1,
    size: 734003200,
  );

  test('the index survives a restart', () {
    final back = DownloadEntry.fromJson(jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>);
    expect(back.toJson(), entry.toJson());
  });

  test('a download plays from local files only', () {
    final item = downloadedPlayItem(entry, '/data/downloads');
    expect(item.url.toString(), 'file:///data/downloads/media_abc123');
    expect(item.artworkPath, '/data/downloads/art_abc123');
    expect(item.headers, isEmpty);
    expect(item.reporter, isNull);
    expect(item.withQuality, isNull);
    expect(item.subtitles.single.url.toFilePath(), '/data/downloads/sub_abc123_0');
    expect(item.subtitles.single.language, 'rus');
  });

  test('download states and sizes read plainly', () {
    expect(stateOf(TaskStatus.enqueued), DownloadState.queued);
    expect(stateOf(TaskStatus.waitingToRetry), DownloadState.queued);
    expect(stateOf(TaskStatus.running), DownloadState.running);
    expect(stateOf(TaskStatus.paused), DownloadState.paused);
    expect(stateOf(TaskStatus.complete), DownloadState.done);
    expect(stateOf(TaskStatus.failed), DownloadState.failed);
    expect(sizeLabel(734003200), '700 MB');
    expect(sizeLabel(1503238554), '1.4 GB');
    expect(entry.copyWith(state: DownloadState.running, progress: .5).title, 'Episode 1');
  });
}
