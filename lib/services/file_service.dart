import 'dart:convert';

import 'package:dynamic_photo_chat_flutter/models/api_response.dart';
import 'package:dynamic_photo_chat_flutter/models/file_upload_response.dart';
import 'package:dynamic_photo_chat_flutter/services/api_config.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class FileService {
  FileService({String? baseUrl, http.Client? httpClient})
      : _baseUrl = baseUrl ?? ApiConfig.apiBaseUrl,
        _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;

  Uri _uri(String path) {
    final base = Uri.parse(_baseUrl);
    return base.replace(path: path.startsWith('/') ? path : '/$path');
  }

  Future<FileUploadResponse> uploadNormal({
    required PlatformFile file,
    int? userId,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/api/files/upload'));
    if (userId != null) {
      req.fields['userId'] = userId.toString();
    }
    req.files.add(await _toMultipart(file, 'file'));
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    final parsed =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final api = ApiResponse.fromJson<Object?>(parsed, (raw) => raw);
    if (!api.success) {
      throw Exception(api.message ?? 'Upload failed');
    }
    return FileUploadResponse.fromJson(api.data);
  }

  Future<FileUploadResponse> uploadLivePhoto({
    required PlatformFile jpeg,
    required PlatformFile mov,
    int? userId,
  }) async {
    final req =
        http.MultipartRequest('POST', _uri('/api/files/upload/live-photo'));
    if (userId != null) {
      req.fields['userId'] = userId.toString();
    }
    req.files.add(await _toMultipart(jpeg, 'jpeg'));
    req.files.add(await _toMultipart(mov, 'mov'));
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    final parsed =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final api = ApiResponse.fromJson<Object?>(parsed, (raw) => raw);
    if (!api.success) {
      throw Exception(api.message ?? 'Upload failed');
    }
    return FileUploadResponse.fromJson(api.data);
  }

  Future<FileUploadResponse> uploadMotionPhoto({
    required PlatformFile file,
    int? userId,
  }) async {
    final req =
        http.MultipartRequest('POST', _uri('/api/files/upload/motion-photo'));
    if (userId != null) {
      req.fields['userId'] = userId.toString();
    }
    req.files.add(await _toMultipart(file, 'file'));
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    final parsed =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final api = ApiResponse.fromJson<Object?>(parsed, (raw) => raw);
    if (!api.success) {
      throw Exception(api.message ?? 'Upload failed');
    }
    return FileUploadResponse.fromJson(api.data);
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
