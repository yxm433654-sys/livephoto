import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vox_flutter/models/api_response.dart';
import 'package:vox_flutter/models/attachment_upload_response.dart';
import 'package:vox_flutter/services/network/api_config.dart';
import 'package:vox_flutter/utils/user_error_message.dart';

class AttachmentService {
  AttachmentService({
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
    } on SocketException {
      throw Exception(
        'Network connection failed. Please check the server address and try again.',
      );
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } catch (error) {
      throw Exception(UserErrorMessage.from(error));
    }
  }

  Future<AttachmentUploadResponse> uploadNormal({
    required PlatformFile file,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload',
      userId: userId,
      files: [await _toMultipart(file, 'file')],
    );
  }

  Future<AttachmentUploadResponse> uploadNormalFromXFile({
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

  Future<AttachmentUploadResponse> uploadNormalFromPath({
    required String filePath,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload',
      userId: userId,
      files: [await http.MultipartFile.fromPath('file', filePath)],
    );
  }

  Future<AttachmentUploadResponse> uploadLivePhoto({
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

  Future<AttachmentUploadResponse> uploadLivePhotoAuto({
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

  Future<AttachmentUploadResponse> uploadMotionPhoto({
    required PlatformFile file,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload/motion-photo',
      userId: userId,
      files: [await _toMultipart(file, 'file')],
    );
  }

  Future<AttachmentUploadResponse> uploadMotionPhotoFromPath({
    required String filePath,
    int? userId,
  }) async {
    return _uploadMultipart(
      path: '/api/files/upload/motion-photo',
      userId: userId,
      files: [await http.MultipartFile.fromPath('file', filePath)],
    );
  }

  Future<AttachmentUploadResponse> preview({required int fileId}) async {
    return _guard(() async {
      final response = await _http
          .get(_uri('/api/files/preview/$fileId'))
          .timeout(_requestTimeout);
      final parsed =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final api = ApiResponse.fromJson<Object?>(parsed, (raw) => raw);
      if (!api.success) {
        throw Exception(api.message ?? 'Attachment preview failed. Please try again.');
      }
      return AttachmentUploadResponse.fromJson(api.data);
    });
  }

  Future<AttachmentUploadResponse> _uploadMultipart({
    required String path,
    required List<http.MultipartFile> files,
    int? userId,
    Map<String, String>? fields,
  }) async {
    return _guard(() async {
      final request = http.MultipartRequest('POST', _uri(path));
      if (userId != null) {
        request.fields['userId'] = userId.toString();
      }
      if (fields != null) {
        request.fields.addAll(fields);
      }
      request.files.addAll(files);

      final streamed = await _http.send(request).timeout(_requestTimeout);
      final response =
          await http.Response.fromStream(streamed).timeout(_requestTimeout);
      final parsed =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final api = ApiResponse.fromJson<Object?>(parsed, (raw) => raw);
      if (!api.success) {
        throw Exception(api.message ?? 'Attachment upload failed. Please try again.');
      }
      return AttachmentUploadResponse.fromJson(api.data);
    });
  }

  Future<http.MultipartFile> _toMultipart(
    PlatformFile file,
    String field,
  ) async {
    if (file.bytes != null) {
      return http.MultipartFile.fromBytes(
        field,
        file.bytes!,
        filename: file.name,
      );
    }
    if (file.path == null) {
      throw Exception('Unable to read the selected file.');
    }
    return http.MultipartFile.fromPath(field, file.path!, filename: file.name);
  }
}

