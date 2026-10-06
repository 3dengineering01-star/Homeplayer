import 'package:flutter/material.dart';

import '../services/quality.dart';

/// App settings: video quality for Wi-Fi and for mobile data.
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
                  'connection. Auto measures the connection before each video. Converted videos have no '
                  'subtitles yet. You can also switch quality while a video plays, with the subtitles '
                  'button in the player.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ]),
    );
  }
}
