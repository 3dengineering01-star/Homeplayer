import 'dart:io';

import 'package:flutter/material.dart';

import '../api/common.dart';

/// Cover of a [PlayItem]: a local file for downloads, otherwise from the server. With
/// [cacheWidth], the picture is decoded that many pixels wide.
Widget artworkImage(PlayItem item, {required Widget fallback, int? cacheWidth}) {
  final path = item.artworkPath;
  if (path != null) {
    return Image.file(File(path), fit: BoxFit.cover, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => fallback);
  }
  if (item.artwork == null) return fallback;
  return Image.network(item.artwork.toString(),
      headers: item.headers, fit: BoxFit.cover, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => fallback);
}
