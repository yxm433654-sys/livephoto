import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dynamic_photo_chat_flutter/models/api_response.dart';
import 'package:dynamic_photo_chat_flutter/models/file_upload_response.dart';
import 'package:dynamic_photo_chat_flutter/services/api_config.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:image_picker/image_picker.dart';

class FileService {
  FileService({
    String? baseUrl,
    http.Client? httpClient,
    Duration? connectionTimeout,
    Duration? requestTimeout,
  })  : _baseUrl = baseUrl ?? ApiConfig.apiBaseUrl,
        _requestTimeout = requestTimeout ?? const Duration(minutes: 10),
        _http = httpClient ??
            IOClient(
              HttpClient()
                ..connectionTimeout =
                    connectionTimeout ?? const Duration(seconds: 12),
            );

  final String _baseUrl;
  final http.Client _http;
  final Duration _requestTimeout;

  Uri _uri(String path) {
    final base = Uri.parse(_baseUrl);
    return base.replace(path: path.startsWith('/') ? path : '/$path');
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on SocketException catch (e) {
      throw Exception(
        '连接失败，请在登录页右上角设置API地址为电脑局域网IP（例如 http://192.168.x.x:8080）: ${e.message}',
      );
    } on TimeoutException {
      throw Exception('请求超时，请检查网络或API地址（登录页右上角可设置）');
    }
  }

  Future<FileUploadResponse> uploadNormal({
    required PlatformFile file,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload',
      userId: userId,
      files: [await _toMultipart(file, 'file')],
    );
  }

  Future<FileUploadResponse> uploadNormalFromXFile({
    required XFile file,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload',
      userId: userId,
      files: [
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: file.name,
        ),
      ],
    );
  }

  Future<FileUploadResponse> uploadNormalFromPath({
    required String filePath,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload',
      userId: userId,
      files: [await http.MultipartFile.fromPath('file', filePath)],
    );
  }

  Future<FileUploadResponse> uploadLivePhoto({
    required PlatformFile jpeg,
    required PlatformFile mov,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload/live-photo',
      userId: userId,
      files: [
        await _toMultipart(jpeg, 'jpeg'),
        await _toMultipart(mov, 'mov'),
      ],
    );
  }

  Future<FileUploadResponse> uploadLivePhotoAuto({
    required String jpegPath,
    required String movPath,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload/live-photo',
      userId: userId,
      files: [
        await http.MultipartFile.fromPath('jpeg', jpegPath),
        await http.MultipartFile.fromPath('mov', movPath),
      ],
    );
  }

  Future<FileUploadResponse> uploadMotionPhoto({
    required PlatformFile file,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload/motion-photo',
      userId: userId,
      files: [await _toMultipart(file, 'file')],
    );
  }

  Future<FileUploadResponse> uploadMotionPhotoFromPath({
    required String filePath,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload/motion-photo',
      userId: userId,
      files: [await http.MultipartFile.fromPath('file', filePath)],
    );
  }

  Future<FileUploadResponse> _uploadMultipart({
    required String path,
    required List<http.MultipartFile> files,
    int? userId,
    Map<String, String>? fields,
  }) async {
    return _guard(() async {
      final req = http.MultipartRequest('POST', _uri(path));
      if (userId != null) {
        req.fields['userId'] = userId.toString();
      }
      if (fields != null) {
        req.fields.addAll(fields);
      }
      req.files.addAll(files);
      final streamed = await _http.send(req).timeout(_requestTimeout);
      final res = await http.Response.fromStream(streamed).timeout(
        _requestTimeout,
      );
      final parsed =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final api = ApiResponse.fromJson<Object?>(parsed, (raw) => raw);
      if (!api.success) {
        throw Exception(api.message ?? 'Upload failed');
      }
      return FileUploadResponse.fromJson(api.data);
    });
  }

  Future<FileUploadResponse> preview({required int fileId}) async {
    return _guard(() async {
      final res = await _http.get(_uri('/api/files/preview/$fileId')).timeout(
            _requestTimeout,
          );
      final parsed =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final api = ApiResponse.fromJson<Object?>(parsed, (raw) => raw);
      if (!api.success) {
        throw Exception(api.message ?? 'Preview failed');
      }
      return FileUploadResponse.fromJson(api.data);
    });
  }

  Future<http.MultipartFile> _toMultipart(
      PlatformFile file, String field) async {
    if (file.bytes != null) {
      return http.MultipartFile.fromBytes(
        field,
        file.bytes!,
        filename: file.name,
      );
    }
    if (file.path == null) {
      throw Exception('File path is null');
    }
    return http.MultipartFile.fromPath(field, file.path!, filename: file.name);
  }
}
