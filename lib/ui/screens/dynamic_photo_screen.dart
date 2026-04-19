import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:vox_flutter/application/message/video_controller_cache.dart';
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
  Completer<bool>? _controllerReadyCompleter;
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
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.setVolume(0));
      unawaited(controller.pause());
      VideoControllerCache.instance.put(widget.videoUrl, controller);
    } else {
      controller?.dispose();
    }
    super.dispose();
  }

  Future<bool> _ensureController() async {
    final existingController = _controller;
    if (existingController != null && existingController.value.isInitialized) {
      return true;
    }

    final inFlight = _controllerReadyCompleter;
    if (inFlight != null) {
      return inFlight.future;
    }

    final completer = Completer<bool>();
    _controllerReadyCompleter = completer;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _loading = true;
      _error = null;
    }

    try {
      final controller =
          await VideoControllerCache.instance.getOrInit(widget.videoUrl);
      if (controller == null) {
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        return false;
      }
      if (!mounted) {
        await controller.dispose();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        return false;
      }
      _controller = controller;
      if (!completer.isCompleted) {
        completer.complete(true);
      }
      return true;
    } catch (e) {
      _error = e.toString();
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      return false;
    } finally {
      _controllerReadyCompleter = null;
      final ratio = _controller?.value.aspectRatio;
      if (mounted) {
        setState(() {
          _loading = false;
          if (ratio != null && ratio.isFinite && ratio > 0) {
            _aspectRatio = ratio;
          }
        });
      } else {
        _loading = false;
        if (ratio != null && ratio.isFinite && ratio > 0) {
          _aspectRatio = ratio;
        }
      }
    }
  }

  Future<void> _startPreview() async {
    _holding = true;
    unawaited(HapticFeedback.heavyImpact());
    final ready = await _ensureController();
    final controller = _controller;
    if (!_holding ||
        !ready ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    await controller.seekTo(Duration.zero);
    if (!_holding) {
      return;
    }
    await controller.play();
    if (mounted && _holding) {
      setState(() => _showVideo = true);
    }
  }

  void _pausePreview({required bool syncUi}) {
    _holding = false;
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.pause());
      unawaited(controller.seekTo(Duration.zero));
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

  Future<void> _saveDynamicPhotoPart(_DynamicPhotoSaveAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case _DynamicPhotoSaveAction.cover:
          await MediaSaver.saveImageFromUrl(
            widget.coverUrl,
            title: widget.title,
          );
          messenger.showSnackBar(
            const SnackBar(content: Text('静态图已保存到系统相册。')),
          );
          break;
        case _DynamicPhotoSaveAction.video:
          await MediaSaver.saveVideoFromUrl(
            widget.videoUrl,
            title: widget.title,
          );
          messenger.showSnackBar(
            const SnackBar(content: Text('视频已保存到系统相册。')),
          );
          break;
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
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
                onSave: _saveDynamicPhotoPart,
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
                              CachedNetworkImage(
                                imageUrl: widget.coverUrl,
                                fit: BoxFit.contain,
                                placeholder: (_, __) =>
                                    const _DetailPlaceholder(),
                                errorWidget: (_, __, ___) =>
                                    const _DetailPlaceholder(),
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
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
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 16,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.58),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Hold to play',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
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
  final Future<void> Function(_DynamicPhotoSaveAction action) onSave;

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
                PopupMenuButton<_DynamicPhotoSaveAction>(
                  onSelected: (value) => unawaited(onSave(value)),
                  color: const Color(0xFF111827),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  itemBuilder: (context) => const [
                    PopupMenuItem<_DynamicPhotoSaveAction>(
                      value: _DynamicPhotoSaveAction.cover,
                      child: Text(
                        '保存静态图',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    PopupMenuItem<_DynamicPhotoSaveAction>(
                      value: _DynamicPhotoSaveAction.video,
                      child: Text(
                        '保存视频',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.download_rounded),
                  iconColor: Colors.white,
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

enum _DynamicPhotoSaveAction { cover, video }
