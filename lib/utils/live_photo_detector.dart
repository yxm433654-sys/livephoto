import 'dart:convert';
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

  static Future<bool> detectMotionPhoto(AssetEntity asset) async {
    if (!Platform.isAndroid) return false;
    if (asset.type != AssetType.image) return false;

    try {
      final file = await asset.file;
      if (file == null) return false;
      return detectMotionPhotoFromPath(file.path);
    } catch (e) {
      return false;
    }
  }

  static Future<bool> detectMotionPhotoFromPath(String filePath) async {
    if (!Platform.isAndroid) return false;

    try {
      final detectors = <MotionPhotoDetector>[
        const GoogleMotionPhotoDetector(),
      ];
      for (final d in detectors) {
        if (await d.matchesFile(filePath)) return true;
      }
      return false;
    } catch (_) {
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

abstract class MotionPhotoDetector {
  const MotionPhotoDetector();
  Future<bool> matchesFile(String filePath);
}

class GoogleMotionPhotoDetector extends MotionPhotoDetector {
  const GoogleMotionPhotoDetector();

  @override
  Future<bool> matchesFile(String filePath) async {
    final f = File(filePath);
    if (!await f.exists()) return false;
    final size = await f.length();
    if (size < 512 * 1024) return false;

    final tail = await _readTail(f, 256 * 1024);
    final s = utf8.decode(tail, allowMalformed: true).toLowerCase();

    final hasXmpHint = s.contains('gcamera:motionphoto') ||
        s.contains('microvideooffset') ||
        s.contains('microvideopresentationtimestampus') ||
        s.contains('container:directory') ||
        s.contains('gcontainer:item');

    if (!hasXmpHint) return false;

    final hasMp4Hint = s.contains('ftyp') &&
        (s.contains('mp42') ||
            s.contains('isom') ||
            s.contains('avc1') ||
            s.contains('qt'));

    return hasMp4Hint;
  }

  Future<List<int>> _readTail(File file, int maxBytes) async {
    final raf = await file.open();
    try {
      final len = await raf.length();
      final start = (len - maxBytes) > 0 ? (len - maxBytes) : 0;
      await raf.setPosition(start);
      return raf.read(maxBytes);
    } finally {
      await raf.close();
    }
  }
}
