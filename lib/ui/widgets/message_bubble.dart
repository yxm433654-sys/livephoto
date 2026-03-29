import 'dart:math' as math;

import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.onPlayVideo,
    required this.onPreviewImage,
  });

  final ChatMessage message;
  final bool isMine;
  final void Function(String url) onPlayVideo;
  final void Function(String url) onPreviewImage;

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
    final bubbleMaxWidth =
        math.min(MediaQuery.of(context).size.width * 0.72, 320.0);
    final mediaWidth = bubbleMaxWidth - 16;
    final mediaHeight = mediaWidth * 0.68;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
        child: Card(
          color: bg,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DefaultTextStyle(
              style: TextStyle(color: fg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _content(context, mediaWidth, mediaHeight),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(time,
                          style: TextStyle(
                              color: fg.withOpacity(0.7), fontSize: 10)),
                      if ((message.status ?? '').isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(message.status ?? '',
                            style: TextStyle(
                                color: fg.withOpacity(0.7), fontSize: 10)),
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

  Widget _content(BuildContext context, double mediaWidth, double mediaHeight) {
    final t = message.type.toUpperCase();
    if (t == 'TEXT') {
      return Text(message.content ?? '');
    }

    if (t == 'IMAGE') {
      final url = message.coverUrl;
      if (url == null || url.isEmpty) return const Text('图片不可用');
      final resolved = _resolveUrl(context, url);
      return GestureDetector(
        onTap: () => onPreviewImage(resolved),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: mediaWidth,
            height: mediaHeight,
            child: ColoredBox(
              color: Colors.black12,
              child: Image.network(
                resolved,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Center(child: Text('图片加载失败')),
              ),
            ),
          ),
        ),
      );
    }

    if (t == 'VIDEO') {
      final video = message.videoUrl;
      final cover = message.coverUrl;
      if ((video == null || video.isEmpty) &&
          (cover == null || cover.isEmpty)) {
        return const Text('视频不可用');
      }
      return _videoPreview(
        mediaWidth: mediaWidth,
        mediaHeight: mediaHeight,
        videoUrl:
            video == null || video.isEmpty ? null : _resolveUrl(context, video),
        coverUrl:
            cover == null || cover.isEmpty ? null : _resolveUrl(context, cover),
      );
    }

    if (t == 'DYNAMIC_PHOTO') {
      final cover = message.coverUrl;
      final video = message.videoUrl;
      if (cover == null || cover.isEmpty || video == null || video.isEmpty) {
        return const Text('动态图片不可用');
      }
      final resolvedCover = _resolveUrl(context, cover);
      final resolvedVideo = _resolveUrl(context, video);
      return _DynamicPhotoPreview(
        coverUrl: resolvedCover,
        videoUrl: resolvedVideo,
        width: mediaWidth,
        height: mediaHeight,
        onTapPreview: () => onPreviewImage(resolvedCover),
      );
    }

    return Text(message.content ?? t);
  }

  Widget _videoPreview({
    required double mediaWidth,
    required double mediaHeight,
    required String? videoUrl,
    required String? coverUrl,
  }) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: mediaWidth,
            height: mediaHeight,
            child: coverUrl == null
                ? Container(
                    color: Colors.black12,
                    child: const Center(
                        child: Icon(Icons.videocam_outlined, size: 28)),
                  )
                : Image.network(
                    coverUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.black12,
                      child: const Center(
                          child: Icon(Icons.videocam_outlined, size: 28)),
                    ),
                  ),
          ),
        ),
        IconButton.filledTonal(
          onPressed: videoUrl == null ? null : () => onPlayVideo(videoUrl),
          icon: const Icon(Icons.play_arrow),
          iconSize: 26,
        ),
      ],
    );
  }

  String _resolveUrl(BuildContext context, String url) {
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      return url;
    }
    final base = Uri.parse(context.read<AppState>().apiBaseUrl);
    final path = url.startsWith('/') ? url : '/$url';
    return base.replace(path: path, query: null, fragment: null).toString();
  }
}

class _DynamicPhotoPreview extends StatefulWidget {
  const _DynamicPhotoPreview({
    required this.coverUrl,
    required this.videoUrl,
    required this.width,
    required this.height,
    required this.onTapPreview,
  });

  final String coverUrl;
  final String videoUrl;
  final double width;
  final double height;
  final VoidCallback onTapPreview;

  @override
  State<_DynamicPhotoPreview> createState() => _DynamicPhotoPreviewState();
}

class _DynamicPhotoPreviewState extends State<_DynamicPhotoPreview> {
  VideoPlayerController? _controller;
  bool _showVideo = false;
  bool _holding = false;
  bool _initing = false;

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
    return GestureDetector(
      onTap: widget.onTapPreview,
      onLongPressStart: (_) => _startPlayback(),
      onLongPressEnd: (_) => _stopPlayback(),
      onLongPressCancel: _stopPlayback,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
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
                right: 6,
                top: 6,
                child: Icon(
                  Icons.motion_photos_on,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
