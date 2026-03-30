import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_photo_chat_flutter/utils/media_downloader.dart';
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
  bool _showVideo = false;
  bool _holding = false;
  bool _initing = false;
  String? _error;
  double _aspectRatio = 3 / 4;
  bool _downloading = true;
  int _received = 0;
  int? _total;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _ensureController() async {
    if (_controller != null) return;
    final downloaded = await MediaDownloader.downloadToTempFile(
      url: widget.videoUrl,
      filenameHint: 'live_${widget.videoUrl.hashCode}.mp4',
      onProgress: (r, t) {
        if (!mounted) return;
        setState(() {
          _received = r;
          _total = t;
        });
      },
    );
    if (!mounted) return;
    setState(() => _downloading = false);
    final c = VideoPlayerController.file(downloaded.file);
    _controller = c;
    c.addListener(_onTick);
    await c.initialize();
    final ar = c.value.aspectRatio;
    if (ar > 0 && ar.isFinite && mounted) {
      setState(() => _aspectRatio = ar);
    }
    await c.setLooping(false);
    await c.setVolume(0);
  }

  void _onTick() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    if (!v.isInitialized) return;
    if (!v.isPlaying) return;
    final d = v.duration;
    if (d == Duration.zero) return;
    if (v.position + const Duration(milliseconds: 80) < d) return;
    _endPlayback();
  }

  Future<void> _startPlayback() async {
    if (_holding) return;
    _holding = true;
    if (_initing) return;
    _initing = true;
    try {
      await HapticFeedback.selectionClick();
      await _ensureController();
      if (!mounted) return;
      // 初始化过程中如果用户松手，则不继续 seek/play。
      if (!_holding) return;
      final c = _controller;
      if (c == null) return;
      await c.seekTo(Duration.zero);
      await c.play();
      if (!mounted) return;
      setState(() => _showVideo = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _initing = false;
    }
  }

  Future<void> _stopPlayback() async {
    _holding = false;
    final c = _controller;
    // 先淡出视频层，减少“按住/松手”时的突兀感。
    if (mounted) setState(() => _showVideo = false);
    if (c == null) {
      return;
    }
    try {
      await c.pause();
      await c.seekTo(Duration.zero);
    } catch (_) {}
  }

  Future<void> _endPlayback() async {
    if (!_showVideo) return;
    final c = _controller;
    if (c == null) return;
    try {
      await c.pause();
      await c.seekTo(Duration.zero);
    } catch (_) {}
    if (mounted) setState(() => _showVideo = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final hasVideo = _showVideo && c != null && c.value.isInitialized;
    final progress = (_total == null || _total == 0)
        ? null
        : (_received / _total!).clamp(0.0, 1.0);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '实况照片')),
      body: Center(
        child: _error != null
            ? Text(_error!)
            : GestureDetector(
                onLongPressStart: (_) => _startPlayback(),
                onLongPressEnd: (_) => _stopPlayback(),
                onLongPressCancel: _stopPlayback,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width - 24,
                      maxHeight: MediaQuery.of(context).size.height - 140,
                    ),
                    child: AspectRatio(
                      aspectRatio: _aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            widget.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: Colors.black12),
                          ),
                          if (_downloading)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black.withOpacity(0.15),
                                alignment: Alignment.center,
                                child: SizedBox(
                                  width: 240,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LinearProgressIndicator(value: progress),
                                      const SizedBox(height: 10),
                                      Text(
                                        progress == null
                                            ? '正在下载视频...'
                                            : '正在下载视频... ${(progress * 100).round()}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        '下载完成后长按播放',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (c != null && c.value.isInitialized)
                            Positioned.fill(
                              child: AnimatedOpacity(
                                duration:
                                    const Duration(milliseconds: 180),
                                opacity: hasVideo ? 1.0 : 0.0,
                                child: AnimatedScale(
                                  duration:
                                      const Duration(milliseconds: 180),
                                  scale: hasVideo ? 1.02 : 1.0,
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: c.value.size.width,
                                      height: c.value.size.height,
                                      child: VideoPlayer(c),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const Positioned(
                            right: 10,
                            top: 10,
                            child: _LiveBadge(),
                          ),
                        ],
                      ),
                    ),
                  ),
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
