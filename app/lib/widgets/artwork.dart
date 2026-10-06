import 'dart:io';

import 'package:flutter/material.dart';

import '../api/common.dart';

/// Cover of a [PlayItem]: a local file for downloads, otherwise from the server.
Widget artworkImage(PlayItem item, {required Widget fallback}) {
  final path = item.artworkPath;
  if (path != null) return Image.file(File(path), fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
  if (item.artwork == null) return fallback;
  return Image.network(item.artwork.toString(),
      headers: item.headers, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
}
