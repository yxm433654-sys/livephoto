import 'dart:io';

import 'package:vox_flutter/utils/media_downloader.dart';
import 'package:photo_manager/photo_manager.dart';

class MediaSaver {
  static Future<void> saveImageFromUrl(String url, {String? title}) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      throw Exception('请先允许访问相册');
    }
    final downloaded = await MediaDownloader.downloadToCacheFile(
      url: url,
      extensionHint: 'jpg',
      onProgress: (_, __) {},
    );
    await PhotoManager.editor.saveImageWithPath(
      downloaded.file.path,
      title: title,
    );
  }

  static Future<void> saveVideoFromUrl(String url, {String? title}) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      throw Exception('请先允许访问相册');
    }
    final downloaded = await MediaDownloader.downloadToCacheFile(
      url: url,
      extensionHint: 'mp4',
      onProgress: (_, __) {},
    );
    await PhotoManager.editor.saveVideo(
      File(downloaded.file.path),
      title: title,
    );
  }
}
