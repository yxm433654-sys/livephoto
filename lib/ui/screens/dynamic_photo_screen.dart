import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _ensureController() async {
    if (_controller != null) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller = c;
    c.addListener(_onTick);
    await c.initialize();
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
    if (c == null) {
      if (_showVideo && mounted) setState(() => _showVideo = false);
      return;
    }
    try {
      await c.pause();
      await c.seekTo(Duration.zero);
    } catch (_) {}
    if (mounted) setState(() => _showVideo = false);
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
                      aspectRatio: hasVideo
                          ? (c.value.aspectRatio == 0
                              ? 16 / 9
                              : c.value.aspectRatio)
                          : 3 / 4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            widget.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: Colors.black12),
                          ),
                          if (hasVideo)
                            FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: c.value.size.width,
                                height: c.value.size.height,
                                child: VideoPlayer(c),
                              ),
                            ),
                          const Positioned(
                            right: 10,
                            top: 10,
                            child: Icon(
                              Icons.motion_photos_on,
                              color: Colors.white,
                              size: 22,
                            ),
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
