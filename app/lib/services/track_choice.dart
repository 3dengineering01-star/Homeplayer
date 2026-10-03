import 'package:media_kit/media_kit.dart';

import '../api/common.dart';

bool _real(String id) => id != 'auto' && id != 'no';

/// The audio track to switch to when a file opens, or null to keep mpv's pick.
/// A remembered language wins if this phone can decode a track in it (the one with most
/// channels); otherwise [forcedId], the fallback chosen because the default can't be decoded.
AudioTrack? chooseAudio(List<AudioTrack> tracks, {String? forcedId, String? preferredLanguage}) {
  final real = tracks.where((t) => _real(t.id)).toList();
  if (preferredLanguage != null) {
    final inLanguage = real.where((t) => t.language == preferredLanguage && canDecodeAudio(t.codec)).toList()
      ..sort((a, b) => (b.channelscount ?? 0).compareTo(a.channelscount ?? 0));
    if (inLanguage.isNotEmpty) return inLanguage.first;
  }
  return forcedId == null ? null : real.where((t) => t.id == forcedId).firstOrNull;
}

/// The subtitle track for a remembered choice: 'off', a language, or null for mpv's pick.
SubtitleTrack? chooseSubtitle(List<SubtitleTrack> tracks, String? preferred) {
  if (preferred == null) return null;
  if (preferred == 'off') return SubtitleTrack.no();
  return tracks.where((t) => _real(t.id) && t.language == preferred).firstOrNull;
}

const _languages = {
  'eng': 'English', 'en': 'English',
  'rus': 'Русский', 'ru': 'Русский',
  'ukr': 'Українська', 'uk': 'Українська',
  'lav': 'Latviešu', 'lv': 'Latviešu',
  'ger': 'Deutsch', 'deu': 'Deutsch', 'de': 'Deutsch',
  'fre': 'Français', 'fra': 'Français', 'fr': 'Français',
  'spa': 'Español', 'es': 'Español',
  'ita': 'Italiano', 'it': 'Italiano',
  'pol': 'Polski', 'pl': 'Polski',
  'jpn': '日本語', 'ja': '日本語',
};

String languageName(String? code) => code == null ? 'Unknown language' : _languages[code] ?? code.toUpperCase();

String _channels(int? n) => switch (n) {
      null => '',
      1 => 'Mono',
      2 => 'Stereo',
      6 => '5.1',
      8 => '7.1',
      final n => '${n}ch',
    };

String _subtitleFormat(String? codec) => switch (codec) {
      null => '',
      'ass' || 'ssa' => 'ASS',
      'subrip' || 'srt' => 'SRT',
      'hdmv_pgs_subtitle' => 'PGS',
      'dvd_subtitle' => 'VobSub',
      'webvtt' => 'VTT',
      'mov_text' => 'TX3G',
      final c => c.toUpperCase(),
    };

String _join(List<String?> parts) =>
    parts.whereType<String>().where((s) => s.isNotEmpty).toSet().join(' · ');

String audioLabel(AudioTrack t) =>
    _join([languageName(t.language), t.title, t.codec == null ? null : codecLabel(t.codec), _channels(t.channelscount)]);

String subtitleLabel(SubtitleTrack t) => _join([languageName(t.language), t.title, _subtitleFormat(t.codec)]);
