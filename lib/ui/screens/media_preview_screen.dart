import 'package:flutter/material.dart';
import 'package:vox_flutter/ui/screens/dynamic_photo_screen.dart';
import 'package:vox_flutter/ui/screens/image_preview_screen.dart';
import 'package:vox_flutter/ui/screens/video_player_screen.dart';

enum MediaPreviewKind {
  image,
  video,
  dynamicPhoto,
}

class MediaPreviewScreen extends StatelessWidget {
  const MediaPreviewScreen.image({
    super.key,
    required this.url,
    this.title,
  })  : kind = MediaPreviewKind.image,
        coverUrl = null,
        videoUrl = null,
        initialAspectRatio = null;

  const MediaPreviewScreen.video({
    super.key,
    required this.url,
    this.title,
  })  : kind = MediaPreviewKind.video,
        coverUrl = null,
        videoUrl = null,
        initialAspectRatio = null;

  const MediaPreviewScreen.dynamicPhoto({
    super.key,
    required this.coverUrl,
    required this.videoUrl,
    this.initialAspectRatio,
    this.title,
  })  : kind = MediaPreviewKind.dynamicPhoto,
        url = null;

  final MediaPreviewKind kind;
  final String? url;
  final String? coverUrl;
  final String? videoUrl;
  final double? initialAspectRatio;
  final String? title;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case MediaPreviewKind.image:
        return ImagePreviewScreen(url: url!, title: title);
      case MediaPreviewKind.video:
        return VideoPlayerScreen(url: url!, title: title);
      case MediaPreviewKind.dynamicPhoto:
        return DynamicPhotoScreen(
          coverUrl: coverUrl!,
          videoUrl: videoUrl!,
          initialAspectRatio: initialAspectRatio,
          title: title,
        );
    }
  }
}
