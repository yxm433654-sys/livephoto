import 'dart:convert';
import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

class DynamicPhotoDetector {
  static Future<DynamicPhotoAsset?> detectIosDynamicPhoto(AssetEntity asset) async {
    if (!Platform.isIOS) return null;
    if (asset.type != AssetType.image) return null;
    if (!asset.isLivePhoto) return null;

    try {
      final file = await asset.file;
      if (file == null) return null;

      final videoFile =
          await asset.originFileWithSubtype ?? await asset.fileWithSubtype;
      if (videoFile == null) return null;

      return DynamicPhotoAsset(
        imagePath: file.path,
        videoPath: videoFile.path,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> detectAndroidMotionPhoto(AssetEntity asset) async {
    if (!Platform.isAndroid) return false;
    if (asset.type != AssetType.image) return false;

    try {
      final file = await asset.file;
      if (file == null) return false;
      return detectAndroidMotionPhotoFromPath(file.path);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> detectAndroidMotionPhotoFromPath(String filePath) async {
    if (!Platform.isAndroid) return false;

    try {
      final detectors = <MotionPhotoSignatureDetector>[
        const GoogleMotionPhotoSignatureDetector(),
      ];
      for (final detector in detectors) {
        if (await detector.matchesFile(filePath)) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

class DynamicPhotoAsset {
  DynamicPhotoAsset({
    required this.imagePath,
    required this.videoPath,
  });

  final String imagePath;
  final String videoPath;
}

abstract class MotionPhotoSignatureDetector {
  const MotionPhotoSignatureDetector();
  Future<bool> matchesFile(String filePath);
}

class GoogleMotionPhotoSignatureDetector extends MotionPhotoSignatureDetector {
  const GoogleMotionPhotoSignatureDetector();

  static const int _tailScanBytes = 32 * 1024 * 1024;
  static const int _minMp4BoxSize = 16;
  static const Set<String> _mp4Brands = <String>{
    'mp41',
    'mp42',
    'isom',
    'iso2',
    'iso3',
    'iso4',
    'iso5',
    'iso6',
    'iso7',
    'iso8',
    'iso9',
    'avc1',
    'hvc1',
    'hev1',
    'mif1',
    'msf1',
    'm4v ',
    'm4a ',
    'f4v ',
    'f4a ',
    'f4p ',
    '3gp4',
    '3gp5',
    '3gp6',
    '3g2a',
    '3g2b',
    '3g2c',
    'dash',
    'cmfc',
    'cmfs',
    'msnv',
    'qt  ',
  };

  @override
  Future<bool> matchesFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return false;
    final size = await file.length();
    if (size < 512 * 1024) return false;

    final head = await _readHead(file, 256 * 1024);
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
        final window = await _readAt(file, videoStart, 64 * 1024);
        if (_hasMp4Ftyp(window)) {
          return true;
        }
      }
    }

    final tail = await _readTail(file, _tailScanBytes);
    return _hasMp4Ftyp(tail);
  }

  bool _hasMp4Ftyp(List<int> bytes) {
    if (bytes.length < 12) {
      return false;
    }

    for (var i = 4; i <= bytes.length - 8; i += 1) {
      if (bytes[i] != 0x66 ||
          bytes[i + 1] != 0x74 ||
          bytes[i + 2] != 0x79 ||
          bytes[i + 3] != 0x70) {
        continue;
      }
      if (!_hasValidMp4BoxHeader(bytes, i - 4)) {
        continue;
      }
      final brand = ascii.decode(bytes.sublist(i + 4, i + 8)).toLowerCase();
      if (_isLikelyMp4Brand(brand)) {
        return true;
      }
    }
    return false;
  }

  bool _hasValidMp4BoxHeader(List<int> bytes, int boxStart) {
    if (boxStart < 0 || boxStart + 8 > bytes.length) {
      return false;
    }

    final boxSize = ((bytes[boxStart] & 0xFF) << 24) |
        ((bytes[boxStart + 1] & 0xFF) << 16) |
        ((bytes[boxStart + 2] & 0xFF) << 8) |
        (bytes[boxStart + 3] & 0xFF);
    if (boxSize == 1) {
      return true;
    }

    final remaining = bytes.length - boxStart;
    return boxSize >= _minMp4BoxSize && boxSize <= remaining;
  }

  bool _isLikelyMp4Brand(String brand) {
    if (brand.length != 4 || !_isPrintableAscii(brand)) {
      return false;
    }
    return _mp4Brands.contains(brand) ||
        brand.startsWith('mp4') ||
        brand.startsWith('iso') ||
        brand.startsWith('3g');
  }

  bool _isPrintableAscii(String value) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x20 || codeUnit > 0x7E) {
        return false;
      }
    }
    return true;
  }

  int? _tryParseVideoOffset(String xmp) {
    final patterns = <RegExp>[
      RegExp(r'microvideooffset\s*=\s*"(\d+)"'),
      RegExp(r'microvideooffset[^0-9]{0,32}(\d{4,})'),
      RegExp(r'item:length\s*=\s*"(\d+)"'),
      RegExp(r'<[^>]*microvideooffset[^>]*>(\d+)</'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(xmp);
      if (match != null) {
        final raw = match.group(1);
        final value = raw == null ? null : int.tryParse(raw);
        if (value != null && value > 0) return value;
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
      final length = await raf.length();
      final safeStart = start < 0 ? 0 : start;
      if (safeStart >= length) return const <int>[];
      await raf.setPosition(safeStart);
      final toRead = (safeStart + maxBytes) > length ? (length - safeStart) : maxBytes;
      return raf.read(toRead);
    } finally {
      await raf.close();
    }
  }

  Future<List<int>> _readTail(File file, int maxBytes) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final start = (length - maxBytes) > 0 ? (length - maxBytes) : 0;
      await raf.setPosition(start);
      return raf.read(maxBytes);
    } finally {
      await raf.close();
    }
  }
}
