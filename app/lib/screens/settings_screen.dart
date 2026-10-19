import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/quality.dart';
import '../services/track_cache.dart';
import '../widgets/appearance_picker.dart';

/// App settings: how the app looks, video quality for Wi-Fi and for mobile data, music on
/// mobile data, and the open-source software inside the app.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ({VideoQuality wifi, VideoQuality mobile})? _quality;

  @override
  void initState() {
    super.initState();
    QualitySettings.load().then((q) {
      if (mounted) setState(() => _quality = q);
    });
    // For the size of the saved songs.
    TrackCache.instance.start().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<VideoQuality?> _pick(String title, VideoQuality current) => showDialog<VideoQuality>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text(title),
          children: [
            RadioGroup<VideoQuality>(
              groupValue: current,
              onChanged: (q) => Navigator.pop(c, q),
              child: Column(children: [
                for (final q in VideoQuality.choices)
                  RadioListTile<VideoQuality>(
                    value: q,
                    title: Text(q.label),
                    subtitle: q.isOriginal || q.isAuto ? Text(q.description) : null,
                  ),
              ]),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = _quality;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: q == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text('Appearance',
                    style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ),
              const AppearancePicker(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
                child: Text('Video quality',
                    style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ),
              ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('On Wi-Fi'),
                subtitle: Text(q.wifi.label),
                onTap: () async {
                  final picked = await _pick('Video quality on Wi-Fi', q.wifi);
                  if (picked == null) return;
                  await QualitySettings.save(wifi: picked);
                  setState(() => _quality = (wifi: picked, mobile: q.mobile));
                },
              ),
              ListTile(
                leading: const Icon(Icons.signal_cellular_alt),
                title: const Text('On mobile data'),
                subtitle: Text(q.mobile.label),
                onTap: () async {
                  final picked = await _pick('Video quality on mobile data', q.mobile);
                  if (picked == null) return;
                  await QualitySettings.save(mobile: picked);
                  setState(() => _quality = (wifi: q.wifi, mobile: picked));
                },
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Above the chosen bitrate the server converts the video, so it plays smoothly on a slow '
                  'connection. Auto measures the connection before each video. Converted videos keep text '
                  'subtitles, but not picture ones (Blu-ray PGS). You can also switch quality while a video plays, with the subtitles '
                  'button in the player.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Music', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ),
              ListTile(
                leading: const Icon(Icons.signal_cellular_alt),
                title: const Text('On mobile data'),
                subtitle: Text(MusicQuality.label(MusicQuality.mobileKbps)),
                onTap: () async {
                  final picked = await showDialog<int>(
                    context: context,
                    builder: (c) => SimpleDialog(
                      title: const Text('Music on mobile data'),
                      children: [
                        RadioGroup<int>(
                          groupValue: MusicQuality.mobileKbps,
                          onChanged: (k) => Navigator.pop(c, k),
                          child: Column(children: [
                            for (final k in MusicQuality.choices)
                              RadioListTile<int>(
                                value: k,
                                title: Text(MusicQuality.label(k)),
                                subtitle: Text(k == 0 ? 'The file as it is, best sound' : 'About ${k * 60 * 60 ~/ 8000} MB an hour'),
                              ),
                          ]),
                        ),
                      ],
                    ),
                  );
                  if (picked == null) return;
                  await MusicQuality.setMobile(picked);
                  setState(() {});
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'Larger files are converted by the server to MP3 of this size, to spend less of your data plan. '
                  'On Wi-Fi and for downloads music always comes as it is. It applies to songs started from now on.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.downloading),
                title: const Text('Save songs ahead'),
                subtitle: Text(TrackCache.instance.ahead == 0
                    ? 'Off'
                    : 'The next ${TrackCache.instance.ahead} songs of the queue · '
                        '${sizeLabel(TrackCache.instance.usedBytes)} saved now'),
                onTap: () async {
                  final picked = await showDialog<int>(
                    context: context,
                    builder: (c) => SimpleDialog(
                      title: const Text('Save songs ahead'),
                      children: [
                        RadioGroup<int>(
                          groupValue: TrackCache.instance.ahead,
                          onChanged: (n) => Navigator.pop(c, n),
                          child: Column(children: [
                            for (final n in TrackCache.choices)
                              RadioListTile<int>(
                                value: n,
                                title: Text(n == 0 ? 'Off' : '$n songs'),
                                subtitle: n == TrackCache.defaultAhead ? const Text('Recommended') : null,
                              ),
                          ]),
                        ),
                      ],
                    ),
                  );
                  if (picked == null) return;
                  await TrackCache.instance.setAhead(picked);
                  setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Delete saved songs'),
                subtitle: Text('${sizeLabel(TrackCache.instance.usedBytes)} of ${sizeLabel(TrackCache.limitBytes)} at most'),
                onTap: () async {
                  await TrackCache.instance.clear();
                  setState(() {});
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'While music plays, the next songs of the queue are saved on the phone, so they play on '
                  'through a tunnel or a dead zone. On mobile data they take data too, at the size chosen '
                  'above. The oldest saved songs are deleted by themselves; downloads are kept apart.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Open-source licenses'),
                subtitle: const Text('The free software OwnMedia is built with'),
                onTap: () async {
                  final info = await PackageInfo.fromPlatform();
                  if (!context.mounted) return;
                  showLicensePage(
                    context: context,
                    applicationName: 'OwnMedia',
                    applicationVersion: info.version,
                  );
                },
              ),
              const SizedBox(height: 16),
            ]),
    );
  }
}
