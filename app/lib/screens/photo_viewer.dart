import 'package:flutter/material.dart';

import '../api/jellyfin.dart';

/// Full-screen photos of one folder: swipe between them, pinch or double-tap to zoom,
/// tap to hide the bar.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.client, required this.photos, required this.initial});

  final JellyfinClient client;
  final List<JellyfinItem> photos;
  final int initial;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  bool _chrome = true;

  /// Zoomed in: swiping would fight with panning the picture.
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Big enough for the screen in physical pixels, small enough to load fast on mobile data.
  int _side(BuildContext context) {
    final size = MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    return size.longestSide.clamp(720, 2560).round();
  }

  ImageProvider _image(BuildContext context, int i) => NetworkImage(
        widget.client.photoUrl(widget.photos[i], maxSide: _side(context)).toString(),
        headers: widget.client.headers,
      );

  void _preload(BuildContext context, int i) {
    for (final n in [i - 1, i + 1]) {
      if (n >= 0 && n < widget.photos.length) precacheImage(_image(context, n), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preload(context, _index);
    });
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _chrome
          ? AppBar(
              backgroundColor: Colors.black45,
              foregroundColor: Colors.white,
              title: Text(widget.photos[_index].name, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text('${_index + 1} / ${widget.photos.length}'),
                  ),
                ),
              ],
            )
          : null,
      body: PageView.builder(
        controller: _pages,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() {
          _index = i;
          _zoomed = false;
        }),
        itemBuilder: (context, i) => _ZoomablePhoto(
          image: _image(context, i),
          onTap: () => setState(() => _chrome = !_chrome),
          onZoom: (zoomed) {
            if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
          },
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.image, required this.onTap, required this.onZoom});

  final ImageProvider image;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoom;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _zoom = TransformationController();
  Offset _doubleTapAt = Offset.zero;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  void _toggleZoom() {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
    } else {
      const scale = 2.5;
      final p = _doubleTapAt;
      _zoom.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    }
    widget.onZoom(_zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _zoom,
        maxScale: 6,
        onInteractionEnd: (_) => widget.onZoom(_zoomed),
        child: SizedBox.expand(
          child: Image(
            image: widget.image,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator(color: Colors.white54)),
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64)),
          ),
        ),
      ),
    );
  }
}
