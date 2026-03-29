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

    final head = await _readHead(f, 256 * 1024);
    final headStr = utf8.decode(head, allowMalformed: true).toLowerCase();

    final hasXmpHint = headStr.contains('gcamera:motionphoto') ||
        headStr.contains('microvideooffset') ||
        headStr.contains('microvideopresentationtimestampus') ||
        headStr.contains('microvideo') ||
        headStr.contains('motionphoto') ||
        headStr.contains('container:directory') ||
        headStr.contains('gcontainer:item');

    if (!hasXmpHint) return false;

    final offset = _tryParseVideoOffset(headStr);
    if (offset != null && offset > 0 && offset < size) {
      final videoStart = size - offset;
      if (videoStart >= 0 && videoStart < size) {
        final win = await _readAt(f, videoStart, 64 * 1024);
        final w = utf8.decode(win, allowMalformed: true).toLowerCase();
        return _hasMp4Ftyp(w);
      }
    }

    final tail = await _readTail(f, 4 * 1024 * 1024);
    final tailStr = utf8.decode(tail, allowMalformed: true).toLowerCase();
    return _hasMp4Ftyp(tailStr);
  }

  bool _hasMp4Ftyp(String s) {
    if (!s.contains('ftyp')) return false;
    return s.contains('mp42') ||
        s.contains('isom') ||
        s.contains('avc1') ||
        s.contains('qt');
  }

  int? _tryParseVideoOffset(String xmp) {
    final patterns = <RegExp>[
      RegExp(r'microvideooffset\\s*=\\s*\"(\\d+)\"'),
      RegExp(r'microvideooffset[^0-9]{0,32}(\\d{4,})'),
      RegExp(r'item:length\\s*=\\s*\"(\\d+)\"'),
      RegExp(r'<[^>]*microvideooffset[^>]*>(\\d+)</'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(xmp);
      if (m != null) {
        final raw = m.group(1);
        final v = raw == null ? null : int.tryParse(raw);
        if (v != null && v > 0) return v;
      }
    }
    return null;
  }

  Future<List<int>> _readHead(File file, int maxBytes) async {
    final raf = await file.open();
    try {
      await raf.setPosition(0);
      return raf.read(maxBytes);
    } finally {
      await raf.close();
    }
  }

  Future<List<int>> _readAt(File file, int start, int maxBytes) async {
    final raf = await file.open();
    try {
      final len = await raf.length();
      final s = start < 0 ? 0 : start;
      if (s >= len) return const <int>[];
      await raf.setPosition(s);
      final toRead = (s + maxBytes) > len ? (len - s) : maxBytes;
      return raf.read(toRead);
    } finally {
      await raf.close();
    }
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
