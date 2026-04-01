import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:vox_flutter/utils/media_saver.dart';

class DynamicPhotoScreen extends StatefulWidget {
  const DynamicPhotoScreen({
    super.key,
    required this.coverUrl,
    required this.videoUrl,
    this.initialAspectRatio,
    this.title,
  });

  final String coverUrl;
  final String videoUrl;
  final double? initialAspectRatio;
  final String? title;

  @override
  State<DynamicPhotoScreen> createState() => _DynamicPhotoScreenState();
}

class _DynamicPhotoScreenState extends State<DynamicPhotoScreen> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _holding = false;
  bool _showVideo = false;
  bool _closing = false;
  String? _error;
  double _aspectRatio = 3 / 4;

  @override
  void initState() {
    super.initState();
    final ratio = widget.initialAspectRatio;
    if (ratio != null && ratio.isFinite && ratio > 0) {
      _aspectRatio = ratio;
    }
    unawaited(_ensureController());
  }

  @override
  void deactivate() {
    _pausePreview(syncUi: false);
    super.deactivate();
  }

  @override
  void dispose() {
    _pausePreview(syncUi: false);
    final controller = _controller;
    _controller = null;
    controller?.setVolume(0);
    controller?.pause();
    controller?.dispose();
    super.dispose();
  }

  Future<void> _ensureController() async {
    if (_controller != null || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(1.0);
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

  Future<void> _startPreview() async {
    _holding = true;
    await HapticFeedback.heavyImpact();
    await _ensureController();
    final controller = _controller;
    if (!_holding || controller == null || !controller.value.isInitialized) {
      return;
    }
    await controller.seekTo(Duration.zero);
    await controller.play();
    if (mounted) {
      setState(() => _showVideo = true);
    }
  }

  void _pausePreview({required bool syncUi}) {
    _holding = false;
    final controller = _controller;
    if (controller != null) {
      controller.pause();
      controller.seekTo(Duration.zero);
    }
    if (syncUi && mounted && _showVideo) {
      setState(() => _showVideo = false);
    } else {
      _showVideo = false;
    }
  }

  Future<void> _stopPreview() async {
    _pausePreview(syncUi: true);
  }

  Future<void> _handleExit() async {
    if (_closing) return;
    _closing = true;
    _pausePreview(syncUi: false);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          unawaited(_handleExit());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _DetailTopBar(
                title: widget.title ?? 'Dynamic Photo',
                onBack: _handleExit,
                onSave: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await MediaSaver.saveImageFromUrl(
                      widget.coverUrl,
                      title: widget.title,
                    );
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Saved cover image to your photo library.',
                        ),
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
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (_) => _startPreview(),
                    onLongPressEnd: (_) => _stopPreview(),
                    onLongPressUp: _stopPreview,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      scale: _holding ? 0.985 : 1.0,
                      child: AspectRatio(
                        aspectRatio: _aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: const Color(0xFF111111)),
                            if (widget.coverUrl.trim().isNotEmpty)
                              Image.network(
                                widget.coverUrl,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) =>
                                    const _DetailPlaceholder(),
                              )
                            else
                              const _DetailPlaceholder(),
                            if (!_showVideo)
                              const Positioned(
                                top: 12,
                                left: 12,
                                child: _LiveBadge(),
                              ),
                            if (_showVideo &&
                                controller != null &&
                                controller.value.isInitialized)
                              FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: controller.value.size.width,
                                  height: controller.value.size.height,
                                  child: VideoPlayer(controller),
                                ),
                              ),
                            if (_loading)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black.withOpacity(0.18),
                                  alignment: Alignment.center,
                                  child: const SizedBox(
                                    width: 220,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 12),
                                        Text(
                                          'Preparing dynamic photo...',
                                          style: TextStyle(
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
                                  color: Colors.black.withOpacity(0.26),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white),
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
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.title,
    required this.onBack,
    required this.onSave,
  });

  final String title;
  final Future<void> Function() onBack;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => unawaited(onBack()),
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
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onSave,
                  icon: const Icon(Icons.download_rounded),
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111111),
      alignment: Alignment.center,
      child: const Icon(
        Icons.photo_outlined,
        size: 42,
        color: Colors.white38,
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.38),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 4,
            backgroundColor: Color(0xFFFF4D4F),
          ),
          SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
