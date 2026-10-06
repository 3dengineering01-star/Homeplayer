import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../api/common.dart';
import '../api/jellyfin.dart';
import '../api/subsonic.dart';
import '../models/account.dart';
import 'downloads.dart';

/// A queue for the player: the tapped track among its neighbours.
typedef CarQueue = ({List<PlayItem> items, int index});

/// What Android Auto (or any media browser) shows: downloads, then each server, as folders
/// and tracks. Music only; Android Auto does not allow video. Media ids carry what is needed
/// to list a folder again: `acc|ACCOUNT`, `jf|ACCOUNT|ITEM`, `ss|ACCOUNT|ar|ARTIST`...,
/// with the account id base64-encoded (it contains ':' and a URL).
class CarLibrary {
  CarLibrary({
    required this.accounts,
    required this.jellyfin,
    required this.subsonic,
    required this.downloads,
    required this.downloadedItem,
  });

  final Future<List<Account>> Function() accounts;
  final Future<JellyfinClient> Function(Account) jellyfin;
  final SubsonicClient Function(Account) subsonic;

  /// Finished audio downloads, in their order.
  final Future<List<DownloadEntry>> Function() downloads;
  final PlayItem Function(DownloadEntry) downloadedItem;

  static const root = AudioService.browsableRootId;
  static const downloadsId = 'downloads';

  /// Library types with music in them; movies, shows and photos stay off the car screen.
  static const _musicTypes = {null, 'music', 'playlists', 'audiobooks', 'mixed', 'folders'};

  // Tracks the car was shown, by id, and what was listed with each, to queue a tapped track
  // with the rest of its album or folder.
  final Map<String, PlayItem> _tracks = {};
  final Map<String, List<String>> _lists = {};
  final Map<String, String> _listOf = {};

  static String _acc(Account a) => base64Url.encode(utf8.encode(a.id));

  Future<Account?> _account(String encoded) async {
    final id = utf8.decode(base64Url.decode(encoded));
    return (await accounts()).where((a) => a.id == id).firstOrNull;
  }

  static MediaItem _folder(String id, String title, {String? subtitle}) =>
      MediaItem(id: id, title: title, artist: subtitle, playable: false);

  MediaItem _track(String listId, String id, PlayItem item, {Duration? duration}) {
    _tracks[id] = item;
    _listOf[id] = listId;
    (_lists[listId] ??= []).add(id);
    return MediaItem(id: id, title: item.title, artist: item.subtitle, duration: duration, playable: true);
  }

  /// The items inside [parentId]. Errors come back as one item saying so: the car shows an
  /// empty list otherwise, which reads as "no music".
  Future<List<MediaItem>> children(String parentId) async {
    _lists.remove(parentId);
    try {
      return await _children(parentId);
    } catch (e) {
      debugPrint('homeplay car: $parentId failed: $e');
      return [MediaItem(id: 'error', title: describeError(e), playable: false)];
    }
  }

  Future<List<MediaItem>> _children(String parentId) async {
    if (parentId == root) {
      final music = await downloads();
      return [
        if (music.isNotEmpty) _folder(downloadsId, 'Downloads', subtitle: '${music.length} tracks'),
        for (final a in await accounts()) _folder('acc|${_acc(a)}', a.serverName, subtitle: a.username),
      ];
    }
    if (parentId == downloadsId) {
      return [for (final e in await downloads()) _track(parentId, 'dl|${e.id}', downloadedItem(e))];
    }
    final parts = parentId.split('|');
    final account = parts.length > 1 ? await _account(parts[1]) : null;
    if (account == null) return const [];
    final acc = parts[1];
    switch (parts) {
      case ['acc', _] when account.kind == ServerKind.jellyfin:
        final client = await jellyfin(account);
        return [
          for (final v in await client.views())
            if (_musicTypes.contains(v.collectionType)) _folder('jf|$acc|${v.id}', v.name),
        ];
      case ['jf', _, final id]:
        final client = await jellyfin(account);
        return [
          for (final i in await client.children(id))
            if (i.isFolder)
              _folder('jf|$acc|${i.id}', i.name, subtitle: i.subtitle)
            else if (i.isPlayable && !i.isVideo)
              _track(parentId, 'jf|$acc|${i.id}', client.toPlayItem(i)),
        ];
      case ['acc', _]:
        return [for (final a in await subsonic(account).artists()) _folder('ss|$acc|ar|${a.id}', a.title, subtitle: a.subtitle)];
      case ['ss', _, 'ar', final id]:
        return [for (final a in await subsonic(account).albums(id)) _folder('ss|$acc|al|${a.id}', a.title, subtitle: a.subtitle)];
      case ['ss', _, 'al', final id]:
        final client = subsonic(account);
        return [
          for (final s in await client.songs(id)) _track(parentId, 'ss|$acc|so|${s.id}', client.toPlayItem(s), duration: s.duration),
        ];
    }
    return const [];
  }

  /// The tapped track with its neighbours, as last listed; null for an id never shown.
  CarQueue? queueFor(String mediaId) {
    final list = _lists[_listOf[mediaId]];
    if (list == null || !_tracks.containsKey(mediaId)) return null;
    final ids = list.where(_tracks.containsKey).toList();
    return (items: [for (final id in ids) _tracks[id]!], index: ids.indexOf(mediaId));
  }

  /// Tracks on every server matching [query]; servers that fail are left out.
  Future<List<MediaItem>> search(String query) async {
    final listId = 'search|$query';
    _lists.remove(listId);
    final found = <MediaItem>[];
    for (final a in await accounts()) {
      final acc = _acc(a);
      try {
        if (a.kind == ServerKind.jellyfin) {
          final client = await jellyfin(a);
          for (final i in await client.searchAudio(query)) {
            found.add(_track(listId, 'jf|$acc|${i.id}', client.toPlayItem(i)));
          }
        } else {
          final client = subsonic(a);
          for (final s in await client.searchSongs(query)) {
            found.add(_track(listId, 'ss|$acc|so|${s.id}', client.toPlayItem(s), duration: s.duration));
          }
        }
      } catch (e) {
        debugPrint('homeplay car search on ${a.serverName} failed: $e');
      }
    }
    return found;
  }

  /// "Play QUERY on Homeplay": the matches from the first; with no query, the downloads.
  Future<CarQueue?> queueForSearch(String query) async {
    final items = query.trim().isEmpty ? await children(downloadsId) : await search(query);
    final first = items.where((i) => i.playable ?? false).firstOrNull;
    return first == null ? null : queueFor(first.id);
  }
}
