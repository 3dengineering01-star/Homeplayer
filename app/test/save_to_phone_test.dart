import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/models/account.dart';
import 'package:homeplay/services/save_to_phone.dart';

void main() {
  test('a saved track keeps its own file name from the server', () {
    final t = JellyfinItem({
      'Id': 'c1', 'Name': 'Cluster One', 'Type': 'Audio', 'Path': r'D:\Music\Bell\01-Cluster One.mp3',
      'Album': 'The Division Bell', 'AlbumArtist': 'Pink Floyd', 'Artists': ['Pink Floyd'],
    });
    expect(phoneFileName(t), '01-Cluster One.mp3');
    expect(phoneFolder(t), 'Homeplay/Pink Floyd/The Division Bell');
  });

  test('without a file name: number, title and the server format; odd characters made safe', () {
    final t = JellyfinItem({
      'Id': 'x', 'Name': 'AC/DC: Live?', 'Type': 'Audio', 'IndexNumber': 3, 'Container': 'flac',
      'Artists': ['AC/DC'],
    });
    expect(phoneFileName(t), '03 AC_DC_ Live_.flac');
    expect(phoneFolder(t), 'Homeplay/AC_DC', reason: 'no album: straight under the artist');
    final bare = JellyfinItem({'Id': 'y', 'Name': '', 'Type': 'Audio'});
    expect(phoneFileName(bare), 'track.mp3');
    expect(phoneFolder(bare), 'Homeplay/Unknown artist');
  });

  test('the original file is asked for, not a stream', () {
    const account = Account(
        id: 'a', kind: ServerKind.jellyfin, baseUrl: 'http://nas:8096', username: 'u', serverName: 'NAS', token: 't', userId: 'me');
    final c = JellyfinClient(account, 'dev');
    expect(c.originalFileUrl(JellyfinItem({'Id': 'c1'})).toString(), 'http://nas:8096/Items/c1/Download');
    expect(JellyfinItem({'Id': 'a', 'Container': 'mov,mp4,m4a'}).container, 'mov');
  });

  test('a track counts as saved only when the file found is in its own folder', () {
    const folder = 'Homeplay/Danheim/Mannavegr', name = '01 Gripir.flac';
    expect(isSavedAt('/storage/emulated/0/Music/Homeplay/Danheim/Mannavegr/01 Gripir.flac', folder, name), isTrue);
    expect(isSavedAt(null, folder, name), isFalse, reason: 'not in Music');
    expect(isSavedAt('/storage/emulated/0/Music/Homeplay/Other/Album/01 Gripir.flac', folder, name), isFalse,
        reason: 'a namesake in another album');
    expect(isSavedAt('/storage/emulated/0/Music/Homeplay/Danheim/Mannavegr/01 Gripir (1).flac', folder, name), isFalse);
  });
}
