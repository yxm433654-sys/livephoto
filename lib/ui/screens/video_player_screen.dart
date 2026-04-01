import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vox_flutter/utils/media_downloader.dart';
import 'package:vox_flutter/utils/media_saver.dart';

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

      final downloaded = await MediaDownloader.downloadToCacheFile(
        url: widget.url,
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
      await controller.play();
      _controller = controller;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _VideoDetailTopBar(
              title: widget.title ?? 'Video',
              onSave: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await MediaSaver.saveVideoFromUrl(
                    widget.url,
                    title: widget.title,
                  );
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Saved to your photo library.'),
                    ),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              },
            ),
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : _loading || controller == null
                        ? SizedBox(
                            width: 220,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                LinearProgressIndicator(value: progress),
                                const SizedBox(height: 12),
                                Text(
                                  progress == null
                                      ? 'Loading video...'
                                      : 'Loading video... ${(progress * 100).round()}%',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          )
                        : AspectRatio(
                            aspectRatio: controller.value.aspectRatio == 0
                                ? 16 / 9
                                : controller.value.aspectRatio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                FittedBox(
                                  fit: BoxFit.contain,
                                  child: SizedBox(
                                    width: controller.value.size.width,
                                    height: controller.value.size.height,
                                    child: VideoPlayer(controller),
                                  ),
                                ),
                                Center(
                                  child: Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.36),
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      onPressed: () async {
                                        if (controller.value.isPlaying) {
                                          await controller.pause();
                                        } else {
                                          await controller.play();
                                        }
                                        if (mounted) {
                                          setState(() {});
                                        }
                                      },
                                      icon: Icon(
                                        controller.value.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
            if (controller != null && controller.value.isInitialized)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoDetailTopBar extends StatelessWidget {
  const _VideoDetailTopBar({
    required this.title,
    required this.onSave,
  });

  final String title;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: Colors.white,
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: onSave,
            icon: const Icon(Icons.download_rounded),
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}




