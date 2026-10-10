import '../api/jellyfin.dart';
import 'search_index.dart';

/// Music as it lies on the server's disk: the folders the person made (styles, artists, albums,
/// whatever they chose) with the tracks in each, built from the tracks' paths alone.

class MusicFolder {
  MusicFolder(this.name, this.path);

  final String name;

  /// Below the library's own folder, "Rock/Pink Floyd"; empty for the library itself.
  final String path;

  /// By name.
  final List<MusicFolder> folders = [];

  /// By file name, the order they have on disk.
  final List<JellyfinItem> tracks = [];

  /// Tracks here and in every folder inside.
  int get trackCount => tracks.length + folders.fold(0, (n, f) => n + f.trackCount);

  List<JellyfinItem> get allTracks => [...tracks, for (final f in folders) ...f.allTracks];

  /// A track whose picture stands for the folder, if any has one.
  JellyfinItem? get cover {
    for (final t in tracks) {
      if (t.albumImageOwner != null || t.hasPrimaryImage) return t;
    }
    for (final f in folders) {
      if (f.cover case final c?) return c;
    }
    return null;
  }
}

List<String> _folderParts(String path) {
  final parts = path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
  return parts.isEmpty ? parts : parts.sublist(0, parts.length - 1);
}

String _sortKey(String s) => s.toLowerCase();

/// The folder tree of [tracks]. Its root is the deepest folder holding them all (the library's
/// own folder); tracks without a path sit in the root.
MusicFolder buildMusicFolders(List<JellyfinItem> tracks) {
  final withParts = [for (final t in tracks) (track: t, parts: t.path == null ? null : _folderParts(t.path!))];
  final paths = [for (final w in withParts) ?w.parts];
  var common = paths.isEmpty ? 0 : paths.first.length;
  for (final p in paths) {
    var i = 0;
    while (i < common && i < p.length && p[i] == paths.first[i]) {
      i++;
    }
    common = i;
  }
  final root = MusicFolder(common == 0 ? '' : paths.first[common - 1], '');
  final children = <MusicFolder, Map<String, MusicFolder>>{};
  for (final (:track, :parts) in withParts) {
    var folder = root;
    if (parts != null) {
      for (final name in parts.skip(common)) {
        final inside = children[folder] ??= {};
        folder = inside[name] ??= () {
          final f = MusicFolder(name, folder.path.isEmpty ? name : '${folder.path}/$name');
          folder.folders.add(f);
          return f;
        }();
      }
    }
    folder.tracks.add(track);
  }
  void sort(MusicFolder f) {
    f.folders.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
    f.tracks.sort((a, b) => _sortKey(a.fileName ?? a.name).compareTo(_sortKey(b.fileName ?? b.name)));
    f.folders.forEach(sort);
  }

  sort(root);
  return root;
}

/// Folders named so, or holding a matching track (then [Hit.inside] has those), at any depth.
List<Hit<MusicFolder>> findFolders(MusicFolder root, String query) {
  final words = queryWords(query);
  if (words.isEmpty) return const [];
  final found = <Hit<MusicFolder>>[];
  void visit(MusicFolder f) {
    for (final sub in f.folders) {
      if (textMatches(sub.name, words)) {
        found.add(Hit(sub, const []));
      } else if ([for (final t in sub.tracks) if (itemMatches(t, words)) t] case final has when has.isNotEmpty) {
        found.add(Hit(sub, has));
      }
      visit(sub);
    }
  }

  visit(root);
  return found;
}
