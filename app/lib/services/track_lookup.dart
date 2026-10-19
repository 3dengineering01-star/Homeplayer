import 'package:flutter/foundation.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../api/lyrics.dart';
import '../api/subsonic.dart';
import '../models/account.dart';
import 'account_store.dart';
import 'downloads.dart';

/// Finds tracks again by their [TrackRef]: their lyrics, songs like them, and a queue saved
/// before the app was closed.
class TrackLookup {
  TrackLookup._();

  static Future<Account?> _account(String? id) async =>
      id == null ? null : (await AccountStore.load()).where((a) => a.id == id).firstOrNull;

  static Future<JellyfinClient?> _jellyfin(String? accountId) async {
    final a = await _account(accountId);
    return a == null || a.kind != ServerKind.jellyfin ? null : JellyfinClient(a, await AccountStore.deviceId());
  }

  static Future<SubsonicClient?> _subsonic(String? accountId) async {
    final a = await _account(accountId);
    return a == null || a.kind == ServerKind.jellyfin ? null : SubsonicClient(a);
  }

  /// [item]'s lyrics from its server; null when it has none or the track has no server.
  static Future<Lyrics?> lyrics(PlayItem item) async {
    final ref = item.ref;
    if (ref == null) return null;
    switch (ref.source) {
      case TrackSource.jellyfin || TrackSource.download:
        return (await _jellyfin(ref.accountId))?.lyrics(ref.id);
      case TrackSource.subsonic:
        return (await _subsonic(ref.accountId))?.lyrics(ref.id, artist: item.subtitle, title: item.title);
    }
  }

  /// Songs like [ref] from its server ("Instant Mix"), without [ref] itself; empty when the
  /// server knows none.
  static Future<List<PlayItem>> instantMix(TrackRef ref) async {
    switch (ref.source) {
      case TrackSource.jellyfin || TrackSource.download:
        final client = await _jellyfin(ref.accountId);
        if (client == null) return const [];
        return [for (final i in await client.instantMix(ref.id)) if (i.id != ref.id) client.toPlayItem(i)];
      case TrackSource.subsonic:
        final client = await _subsonic(ref.accountId);
        if (client == null) return const [];
        return [for (final s in await client.similarSongs(ref.id)) if (s.id != ref.id) client.toPlayItem(s)];
    }
  }

  /// The tracks of a saved queue, in its order. Tracks whose server, account or download is
  /// gone are left out; a server that does not answer leaves out its tracks only.
  static Future<Map<TrackRef, PlayItem>> rebuild(List<TrackRef> refs) async {
    final found = <TrackRef, PlayItem>{};
    final downloaded = refs.where((r) => r.source == TrackSource.download).toList();
    if (downloaded.isNotEmpty) {
      final downloads = Downloads.instance;
      await downloads.init();
      for (final r in downloaded) {
        final e = downloads.find(r.id);
        if (e != null && e.state == DownloadState.done && !e.isVideo) found[r] = downloads.toPlayItem(e);
      }
    }
    final byAccount = <(TrackSource, String?), List<TrackRef>>{};
    for (final r in refs.where((r) => r.source != TrackSource.download)) {
      (byAccount[(r.source, r.accountId)] ??= []).add(r);
    }
    for (final MapEntry(key: (source, accountId), value: list) in byAccount.entries) {
      try {
        if (source == TrackSource.jellyfin) {
          final client = await _jellyfin(accountId);
          if (client == null) continue;
          final items = await client.itemsByIds([for (final r in list) r.id]);
          for (final i in items) {
            found[TrackRef(source, i.id, accountId: accountId)] = client.toPlayItem(i);
          }
        } else {
          final client = await _subsonic(accountId);
          if (client == null) continue;
          // One request per song: a few at a time.
          for (var at = 0; at < list.length; at += 8) {
            final chunk = list.skip(at).take(8);
            final songs = await Future.wait(chunk.map((r) => client.song(r.id)));
            for (final s in songs.nonNulls) {
              found[TrackRef(source, s.id, accountId: accountId)] = client.toPlayItem(s);
            }
          }
        }
      } catch (e) {
        debugPrint('homeplay saved queue: tracks of one server not loaded: $e');
      }
    }
    return found;
  }
}
