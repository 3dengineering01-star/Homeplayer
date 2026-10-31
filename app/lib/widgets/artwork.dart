import 'dart:io';

import 'package:flutter/material.dart';

import '../api/common.dart';
import '../services/artwork_cache.dart';

/// Cover of a [PlayItem]: the file kept with a download, otherwise from the server through
/// [ArtworkCache]. With [cacheWidth], the picture is decoded that many pixels wide.
Widget artworkImage(PlayItem item, {required Widget fallback, int? cacheWidth}) {
  final path = item.artworkPath;
  if (path != null) {
    return Image.file(File(path), fit: BoxFit.cover, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => fallback);
  }
  final url = item.artwork;
  if (url == null) return fallback;
  return serverImage(url, headers: item.headers, fallback: fallback, cacheWidth: cacheWidth);
}

/// A picture from the server, kept on the phone so it shows again without a connection.
/// [fallback] shows while it loads and when there is none; with [fade] the picture fades in
/// over it (the fallback then needs a bounded size).
Widget serverImage(
  Uri url, {
  Map<String, String> headers = const {},
  required Widget fallback,
  BoxFit fit = BoxFit.cover,
  int? cacheWidth,
  bool fade = false,
}) =>
    Image(
      image: ResizeImage.resizeIfNeeded(cacheWidth, null, CachedArtwork(url, headers: headers)),
      fit: fit,
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        if (!fade) return frame == null ? fallback : child;
        return Stack(fit: StackFit.expand, children: [
          fallback,
          AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 250), child: child),
        ]);
      },
    );
