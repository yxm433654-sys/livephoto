import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.url));
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '视频')),
      body: Center(
        child: _error != null
            ? Text(_error!)
            : _loading || _controller == null
                ? const CircularProgressIndicator()
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
