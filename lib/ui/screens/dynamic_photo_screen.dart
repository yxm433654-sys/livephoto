import 'package:dynamic_photo_chat_flutter/utils/media_downloader.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class DynamicPhotoScreen extends StatefulWidget {
  const DynamicPhotoScreen({
    super.key,
    required this.coverUrl,
    required this.videoUrl,
    this.title,
  });

  final String coverUrl;
  final String videoUrl;
  final String? title;

  @override
  State<DynamicPhotoScreen> createState() => _DynamicPhotoScreenState();
}

class _DynamicPhotoScreenState extends State<DynamicPhotoScreen> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _showVideo = false;
  String? _error;
  double _aspectRatio = 3 / 4;
  int _received = 0;
  int? _total;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _ensureController() async {
    if (_controller != null) return;

    setState(() {
      _loading = true;
      _error = null;
      _received = 0;
      _total = null;
    });

    try {
      final downloaded = await MediaDownloader.downloadToCacheFile(
        url: widget.videoUrl,
        extensionHint: 'mp4',
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );

      final controller = VideoPlayerController.file(downloaded.file);
      await controller.initialize();
      await controller.setLooping(true);
      controller.addListener(_syncPlaybackState);

      final ratio = controller.value.aspectRatio;
      if (ratio.isFinite && ratio > 0) {
        _aspectRatio = ratio;
      }

      _controller = controller;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _syncPlaybackState() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final isPlaying = controller.value.isPlaying;
    if (_showVideo != isPlaying) {
      setState(() => _showVideo = isPlaying);
    }
  }

  Future<void> _togglePlayback() async {
    await _ensureController();
    final controller = _controller;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) {
        setState(() => _showVideo = false);
      }
      return;
    }

    await controller.seekTo(Duration.zero);
    await controller.play();
    if (mounted) {
      setState(() => _showVideo = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showVideoLayer =
        _showVideo && controller != null && controller.value.isInitialized;
    final progress = (_total == null || _total == 0)
        ? null
        : (_received / _total!).clamp(0.0, 1.0);
    final hasCover = widget.coverUrl.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? 'Live Photo'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: _togglePlayback,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: AspectRatio(
                        aspectRatio: _aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF111827),
                                    Color(0xFF1D4ED8),
                                    Color(0xFF0F172A),
                                  ],
                                ),
                              ),
                            ),
                            if (hasCover)
                              Image.network(
                                widget.coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            if (showVideoLayer)
                              FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: controller.value.size.width,
                                  height: controller.value.size.height,
                                  child: VideoPlayer(controller),
                                ),
                              ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.12),
                                    Colors.black.withOpacity(0.28),
                                  ],
                                ),
                              ),
                            ),
                            const Positioned(
                              left: 14,
                              top: 14,
                              child: _LiveBadge(),
                            ),
                            if (_loading)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black.withOpacity(0.22),
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: 220,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        LinearProgressIndicator(value: progress),
                                        const SizedBox(height: 12),
                                        Text(
                                          progress == null
                                              ? 'Preparing video...'
                                              : 'Preparing video... ${(progress * 100).round()}%',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (_error != null)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black.withOpacity(0.35),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            Align(
                              alignment: Alignment.center,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 180),
                                opacity: _loading ? 0.0 : 1.0,
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.34),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Icon(
                                    showVideoLayer ? Icons.pause : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                            ),
                            const Positioned(
                              left: 18,
                              right: 18,
                              bottom: 18,
                              child: Text(
                                'Tap to preview the motion. Tap again to pause.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Text(
                  'If the cover is still processing, the placeholder stays visible until the video is ready.',
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFF4D4F),
              ),
            ),
          ),
          SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.0,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
