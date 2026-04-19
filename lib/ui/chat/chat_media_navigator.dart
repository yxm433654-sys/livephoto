import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vox_flutter/ui/screens/media_preview_screen.dart';

class ChatMediaNavigator {
  ChatMediaNavigator(this.context);

  final BuildContext context;
  bool _openingDynamicPhoto = false;

  void openPlayer(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen.video(url: url),
      ),
    );
  }

  void openImagePreview(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen.image(url: url),
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
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaPreviewScreen.dynamicPhoto(
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
