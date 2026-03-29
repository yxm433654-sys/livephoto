import 'dart:io';
import 'package:photo_manager/photo_manager.dart';

class LivePhotoDetector {
  /// 检测是否是iOS Live Photo
  static Future<LivePhotoInfo?> detectLivePhoto(AssetEntity asset) async {
    if (!Platform.isIOS) return null;
    if (asset.type != AssetType.image) return null;
    if (!asset.isLivePhoto) return null;

    try {
      final file = await asset.file;
      if (file == null) return null;

      final videoFile =
          await asset.originFileWithSubtype ?? await asset.fileWithSubtype;
      if (videoFile == null) return null;

      return LivePhotoInfo(
        imagePath: file.path,
        videoPath: videoFile.path,
      );
    } catch (e) {
      return null;
    }
  }

  /// 检测是否是Android Motion Photo
  static Future<bool> detectMotionPhoto(AssetEntity asset) async {
    if (!Platform.isAndroid) return false;
    if (asset.type != AssetType.image) return false;

    try {
      final file = await asset.file;
      if (file == null) return false;

      final size = await file.length();
      return size > 5 * 1024 * 1024;
    } catch (e) {
      return false;
    }
  }
}

class LivePhotoInfo {
  final String imagePath;
  final String videoPath;

  LivePhotoInfo({
    required this.imagePath,
    required this.videoPath,
  });
}
