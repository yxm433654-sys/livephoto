import 'dart:async';

import 'package:video_player/video_player.dart';

class VideoControllerCache {
  VideoControllerCache._();

  static final VideoControllerCache instance = VideoControllerCache._();

  final Map<String, VideoPlayerController> _cache = {};
  final Map<String, Future<void>> _pending = {};

  Future<void> warmup(String url) async {
    if (_cache.containsKey(url) || _pending.containsKey(url)) {
      return;
    }

    final future = _initialize(url);
    _pending[url] = future;
    try {
      await future;
    } finally {
      _pending.remove(url);
    }
  }

  Future<VideoPlayerController?> getOrInit(String url) async {
    final cached = take(url);
    if (cached != null) {
      return cached;
    }

    final inFlight = _pending[url];
    if (inFlight != null) {
      await inFlight;
      return take(url);
    }

    await warmup(url);
    return take(url);
  }

  VideoPlayerController? take(String url) {
    return _cache.remove(url);
  }

  void put(String url, VideoPlayerController controller) {
    final existing = _cache.remove(url);
    existing?.dispose();
    _cache[url] = controller;
  }

  Future<void> _initialize(String url) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(1.0);
      _cache[url] = controller;
      controller = null;
    } catch (_) {
      await controller?.dispose();
    }
  }

  Future<void> disposeAll() async {
    final controllers = _cache.values.toList(growable: false);
    _cache.clear();
    for (final controller in controllers) {
      await controller.dispose();
    }
  }
}
