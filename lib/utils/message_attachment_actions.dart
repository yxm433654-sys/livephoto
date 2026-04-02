import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vox_flutter/application/message/media_url_resolver.dart';
import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/utils/media_downloader.dart';
import 'package:vox_flutter/utils/media_saver.dart';

class MessageAttachmentActions {
  const MessageAttachmentActions._();

  static Future<void> openFileMessage({
    required ChatMessage message,
    required MediaUrlResolver urlResolver,
  }) async {
    final downloadUrl = _downloadUrl(message, urlResolver);
    if (downloadUrl == null) {
      throw Exception('This file is not ready to open yet.');
    }

    final result = await MediaDownloader.downloadToCacheFile(
      url: downloadUrl,
      extensionHint: _extensionHint(message),
      onProgress: (_, __) {},
    );
    final openResult = await OpenFilex.open(result.file.path);
    if (openResult.type != ResultType.done) {
      throw Exception(
        openResult.message.isEmpty
            ? 'Unable to open this file.'
            : openResult.message,
      );
    }
  }

  static Future<String> saveToLocal({
    required ChatMessage message,
    required MediaUrlResolver urlResolver,
  }) async {
    final type = message.type.toUpperCase();
    if (type == 'IMAGE') {
      final url = _imageUrl(message, urlResolver);
      if (url == null) {
        throw Exception('The image is not ready yet.');
      }
      await MediaSaver.saveImageFromUrl(url, title: _safeFileName(message));
      return 'Saved to the system gallery.';
    }
    if (type == 'VIDEO' || type == 'DYNAMIC_PHOTO') {
      final url = _videoUrl(message, urlResolver);
      if (url == null) {
        throw Exception('The video is not ready yet.');
      }
      await MediaSaver.saveVideoFromUrl(url, title: _safeFileName(message));
      return 'Saved to the system gallery.';
    }
    if (type == 'FILE') {
      final url = _downloadUrl(message, urlResolver);
      if (url == null) {
        throw Exception('The file is not ready yet.');
      }
      final downloaded = await MediaDownloader.downloadToCacheFile(
        url: url,
        extensionHint: _extensionHint(message),
        onProgress: (_, __) {},
      );
      final baseDir =
          await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final voxDir = Directory('${baseDir.path}${Platform.pathSeparator}Vox');
      if (!await voxDir.exists()) {
        await voxDir.create(recursive: true);
      }
      final fileName = _dedupeFileName(voxDir, _safeFileName(message));
      final savedFile = await downloaded.file.copy(
        '${voxDir.path}${Platform.pathSeparator}$fileName',
      );
      return 'Saved to ${savedFile.path}';
    }
    throw Exception('This message type cannot be saved yet.');
  }

  static String _dedupeFileName(Directory directory, String fileName) {
    final normalized = fileName.trim().isEmpty ? 'attachment' : fileName.trim();
    final dot = normalized.lastIndexOf('.');
    final hasExt = dot > 0 && dot < normalized.length - 1;
    final base = hasExt ? normalized.substring(0, dot) : normalized;
    final ext = hasExt ? normalized.substring(dot) : '';
    var candidate = normalized;
    var index = 1;
    while (File('${directory.path}${Platform.pathSeparator}$candidate').existsSync()) {
      candidate = '${base}_$index$ext';
      index += 1;
    }
    return candidate;
  }

  static String _safeFileName(ChatMessage message) {
    final raw = (message.content ?? '').trim();
    if (raw.isNotEmpty) {
      return raw.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
    }
    return 'attachment.${_extensionHint(message)}';
  }

  static String _extensionHint(ChatMessage message) {
    final name = (message.content ?? '').trim().toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) {
      return name.substring(dot + 1);
    }
    final type = message.type.toUpperCase();
    if (type == 'IMAGE') return 'jpg';
    if (type == 'VIDEO' || type == 'DYNAMIC_PHOTO') return 'mp4';
    final source = (message.media?.sourceType ?? '').toLowerCase();
    if (source.contains('pdf')) return 'pdf';
    if (source.contains('word') || source.contains('doc')) return 'docx';
    if (source.contains('sheet') || source.contains('excel') || source.contains('xls')) {
      return 'xlsx';
    }
    if (source.contains('presentation') || source.contains('ppt')) return 'pptx';
    if (source.contains('zip')) return 'zip';
    if (source.contains('rar')) return 'rar';
    if (source.contains('text/plain')) return 'txt';
    return 'bin';
  }

  static String? _downloadUrl(ChatMessage message, MediaUrlResolver urlResolver) {
    final fileUrl = message.resolvedPlayUrl;
    if (fileUrl != null && fileUrl.trim().isNotEmpty) {
      return urlResolver.resolve(fileUrl);
    }
    final coverUrl = message.resolvedCoverUrl;
    if (coverUrl != null && coverUrl.trim().isNotEmpty) {
      return urlResolver.resolve(coverUrl);
    }
    return null;
  }

  static String? _imageUrl(ChatMessage message, MediaUrlResolver urlResolver) {
    final url = message.resolvedCoverUrl;
    if (url == null || url.trim().isEmpty) {
      return null;
    }
    return urlResolver.resolve(url);
  }

  static String? _videoUrl(ChatMessage message, MediaUrlResolver urlResolver) {
    final url = message.resolvedPlayUrl;
    if (url == null || url.trim().isEmpty) {
      return null;
    }
    return urlResolver.resolve(url);
  }
}
