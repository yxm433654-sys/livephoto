import 'package:flutter/material.dart';
import 'package:dynamic_photo_chat_flutter/utils/media_downloader.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.url, this.title});

  final String url;
  final String? title;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;
  int _received = 0;
  int? _total;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
        _received = 0;
        _total = null;
      });

      final downloaded = await MediaDownloader.downloadToTempFile(
        url: widget.url,
        filenameHint: 'video_${widget.url.hashCode}.mp4',
        onProgress: (r, t) {
          if (!mounted) return;
          setState(() {
            _received = r;
            _total = t;
          });
        },
      );

      final controller = VideoPlayerController.file(downloaded.file);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_total == null || _total == 0)
        ? null
        : (_received / _total!).clamp(0.0, 1.0);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '视频')),
      body: Center(
        child: _error != null
            ? Text(_error!)
            : _loading || _controller == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 220,
                        child: LinearProgressIndicator(value: progress),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        progress == null
                            ? '正在下载...'
                            : '正在下载... ${(progress * 100).round()}%',
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ],
                  )
                : AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio == 0
                        ? 16 / 9
                        : _controller!.value.aspectRatio,
                    child: Stack(
                      children: [
                        VideoPlayer(_controller!),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: VideoProgressIndicator(_controller!,
                              allowScrubbing: true),
                        ),
                        Center(
                          child: IconButton.filledTonal(
                            onPressed: () async {
                              if (_controller == null) return;
                              if (_controller!.value.isPlaying) {
                                await _controller!.pause();
                              } else {
                                await _controller!.play();
                              }
                              if (mounted) setState(() {});
                            },
                            icon: Icon(_controller!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
