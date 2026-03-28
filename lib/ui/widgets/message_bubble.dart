import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.onPlayVideo,
    required this.resolveUrl,
  });

  final ChatMessage message;
  final bool isMine;
  final void Function(String url) onPlayVideo;
  final String Function(String url) resolveUrl;

  @override
  Widget build(BuildContext context) {
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isMine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    final fg = isMine
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSecondaryContainer;

    final time = message.createdAt == null
        ? ''
        : DateFormat('HH:mm:ss').format(message.createdAt!.toLocal());

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Card(
          color: bg,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DefaultTextStyle(
              style: TextStyle(color: fg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _content(context),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(time,
                          style: TextStyle(
                              color: fg.withOpacity(0.7), fontSize: 11)),
                      if (!isMine) ...[
                        const SizedBox(width: 8),
                        Text(message.status ?? '',
                            style: TextStyle(
                                color: fg.withOpacity(0.7), fontSize: 11)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final t = message.type.toUpperCase();
    if (t == 'TEXT') {
      return Text(
        message.content ?? '',
        style: const TextStyle(fontSize: 15, height: 1.3),
      );
    }

    if (t == 'IMAGE') {
      final url =
          message.coverUrl == null ? null : resolveUrl(message.coverUrl!);
      if (url == null || url.isEmpty) return const Text('图片不可用');
      return _mediaFrame(
        child: Image.network(url, fit: BoxFit.contain),
      );
    }

    if (t == 'VIDEO') {
      final raw = message.videoUrl ?? message.coverUrl;
      final url = raw == null ? null : resolveUrl(raw);
      if (url == null || url.isEmpty) return const Text('视频不可用');
      return _videoPreview(url);
    }

    if (t == 'DYNAMIC_PHOTO') {
      final cover = message.coverUrl;
      final video = message.videoUrl;
      if (cover == null || cover.isEmpty || video == null || video.isEmpty) {
        return const Text('动态图片不可用');
      }
      final coverUrl = resolveUrl(cover);
      final videoUrl = resolveUrl(video);
      return _LivePhotoWidget(
        coverUrl: coverUrl,
        videoUrl: videoUrl,
        onTapPlay: () => onPlayVideo(videoUrl),
      );
    }

    return Text(message.content ?? t);
  }

  Widget _videoPreview(String url) {
    return _mediaFrame(
      maxHeight: 140,
      maxWidth: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _VideoThumbnail(url: url),
          IconButton.filledTonal(
            onPressed: () => onPlayVideo(url),
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      ),
    );
  }

  Widget _mediaFrame({
    required Widget child,
    double maxWidth = 220,
    double maxHeight = 220,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0x11000000)),
          child: child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Live Photo 长按自动播放组件
// ═══════════════════════════════════════════════════════════════════

class _LivePhotoWidget extends StatefulWidget {
  const _LivePhotoWidget({
    required this.coverUrl,
    required this.videoUrl,
    required this.onTapPlay,
  });

  final String coverUrl;
  final String videoUrl;
  final VoidCallback onTapPlay;

  @override
  State<_LivePhotoWidget> createState() => _LivePhotoWidgetState();
}

class _LivePhotoWidgetState extends State<_LivePhotoWidget>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _playing = false;
  bool _initialized = false;
  bool _preloading = false;

  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _preloadVideo();
  }

  @override
  void didUpdateWidget(covariant _LivePhotoWidget old) {
    super.didUpdateWidget(old);
    if (old.videoUrl != widget.videoUrl) {
      _disposeController();
      _preloadVideo();
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _initialized = false;
    _preloading = false;
  }

  /// 预加载视频控制器（不播放），使长按时可以立即启动
  Future<void> _preloadVideo() async {
    if (_preloading) return;
    _preloading = true;
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0); // 默认静音，避免在聊天列表中打扰
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      debugPrint('Live Photo preload error: $e');
    }
  }

  /// 长按开始 → 播放视频
  void _onLongPressStart(LongPressStartDetails _) async {
    if (!_initialized || _controller == null) return;
    setState(() => _playing = true);
    _fadeCtrl.forward();
    await _controller!.seekTo(Duration.zero);
    await _controller!.play();
  }

  /// 长按结束 → 停止播放，切回封面
  void _onLongPressEnd(LongPressEndDetails _) => _stopPlaying();

  void _onLongPressCancel() => _stopPlaying();

  void _stopPlaying() async {
    if (!_playing) return;
    await _controller?.pause();
    _fadeCtrl.reverse();
    if (mounted) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
        child: GestureDetector(
          onLongPressStart: _onLongPressStart,
          onLongPressEnd: _onLongPressEnd,
          onLongPressCancel: _onLongPressCancel,
          onTap: widget.onTapPlay,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 封面图
              DecoratedBox(
                decoration: const BoxDecoration(color: Color(0x11000000)),
                child: Image.network(widget.coverUrl, fit: BoxFit.contain),
              ),

              // 视频层（长按时淡入）
              if (_initialized && _controller != null)
                FadeTransition(
                  opacity: _fadeCtrl,
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: _controller!.value.size.width,
                        height: _controller!.value.size.height,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                  ),
                ),

              // LIVE 角标
              Positioned(
                top: 6,
                left: 6,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _playing
                        ? Colors.amber.withOpacity(0.9)
                        : Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.motion_photos_on,
                        size: 12,
                        color: _playing ? Colors.black87 : Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _playing ? Colors.black87 : Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 非播放时显示全屏播放按钮提示
              if (!_playing)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 普通视频缩略图
// ═══════════════════════════════════════════════════════════════════

class _VideoThumbnail extends StatefulWidget {
  const _VideoThumbnail({required this.url});

  final String url;

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _controller;
  Future<void>? _init;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = c;
    _init = _initialize(c);
  }

  Future<void> _initialize(VideoPlayerController c) async {
    await c.initialize();
    await c.pause();
    await c.seekTo(Duration.zero);
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _controller?.dispose();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = c;
    _init = _initialize(c);
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return const ColoredBox(color: Colors.black12);
    }
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Colors.black12,
            child: Center(child: Icon(Icons.videocam_outlined)),
          );
        }
        if (!c.value.isInitialized) {
          return const ColoredBox(
            color: Colors.black12,
            child: Center(child: Icon(Icons.videocam_outlined)),
          );
        }
        return FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        );
      },
    );
  }
}
