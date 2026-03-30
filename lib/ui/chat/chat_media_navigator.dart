import 'package:dynamic_photo_chat_flutter/ui/screens/dynamic_photo_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/image_preview_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/video_player_screen.dart';
import 'package:flutter/material.dart';

class ChatMediaNavigator {
  ChatMediaNavigator(this.context);

  final BuildContext context;
  bool _openingDynamicPhoto = false;

  void openPlayer(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(url: url),
      ),
    );
  }

  void openImagePreview(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImagePreviewScreen(url: url),
      ),
    );
  }

  Future<void> openDynamicPhoto(
    String coverUrl,
    String videoUrl,
    double aspectRatio,
  ) async {
    if (_openingDynamicPhoto) return;
    _openingDynamicPhoto = true;
    if (coverUrl.trim().isNotEmpty) {
      try {
        await precacheImage(NetworkImage(coverUrl), context);
      } catch (_) {}
      if (!context.mounted) {
        _openingDynamicPhoto = false;
        return;
      }
    }
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DynamicPhotoScreen(
            coverUrl: coverUrl,
            videoUrl: videoUrl,
            initialAspectRatio: aspectRatio,
          ),
        ),
      );
    } finally {
      _openingDynamicPhoto = false;
    }
  }
}
