import 'dart:convert';

import 'package:vox_flutter/models/api_response.dart';
import 'package:vox_flutter/services/network/api_config.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({String? baseUrl, http.Client? httpClient})
      : _baseUrl = baseUrl ?? ApiConfig.apiBaseUrl,
        _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;

  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(_baseUrl);
    return base.replace(
      path: path.startsWith('/') ? path : '/$path',
      queryParameters: query,
    );
  }

  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, String>? query,
    required T Function(Object? raw) decode,
  }) async {
    final res = await _http.get(uri(path, query));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return ApiResponse.fromJson<T>(body, decode);
  }

  Future<ApiResponse<T>> postJson<T>(
    String path, {
    required Object body,
    required T Function(Object? raw) decode,
  }) async {
    final res = await _http.post(
      uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final parsed =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return ApiResponse.fromJson<T>(parsed, decode);
  }

  Future<ApiResponse<T>> putJson<T>(
    String path, {
    Object? body,
    required T Function(Object? raw) decode,
  }) async {
    final res = await _http.put(
      uri(path),
      headers: {'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    final parsed =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return ApiResponse.fromJson<T>(parsed, decode);
  }

  Future<ApiResponse<T>> delete<T>(
    String path, {
    Map<String, String>? query,
    Object? body,
    required T Function(Object? raw) decode,
  }) async {
    final res = await _http.delete(
      uri(path, query),
      headers: {'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    final parsed =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return ApiResponse.fromJson<T>(parsed, decode);
  }
}
