import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DownloadResult {
  DownloadResult({required this.file, required this.bytes});
  final File file;
  final int bytes;
}

class MediaDownloader {
  static Future<DownloadResult> downloadToTempFile({
    required String url,
    required String filenameHint,
    required void Function(int received, int? total) onProgress,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await c.send(req);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('下载失败: HTTP ${res.statusCode}');
      }

      final dir = await getTemporaryDirectory();
      final safeName = filenameHint
          .replaceAll('\\', '_')
          .replaceAll('/', '_')
          .replaceAll(':', '_')
          .trim();
      final out = File('${dir.path}/$safeName');
      if (await out.exists()) {
        // 直接复用，避免重复下载
        final len = await out.length();
        onProgress(len, len);
        return DownloadResult(file: out, bytes: len);
      }

      final len = res.contentLength;
      final total = (len != null && len > 0) ? len : null;
      final sink = out.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          received += chunk.length;
          sink.add(chunk);
          onProgress(received, total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      return DownloadResult(file: out, bytes: received);
    } finally {
      if (client == null) {
        c.close();
      }
    }
  }
}

