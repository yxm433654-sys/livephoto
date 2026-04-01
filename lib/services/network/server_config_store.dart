import 'package:vox_flutter/services/network/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServerEndpoints {
  const ServerEndpoints({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
  });

  final String apiBaseUrl;
  final String wsBaseUrl;
}

class ServerConfigStore {
  static const _apiBaseKey = 'apiBaseUrl';
  static const _wsBaseKey = 'wsBaseUrl';

  Future<ServerEndpoints> load(SharedPreferences preferences) async {
    final savedApiBaseUrl = preferences.getString(_apiBaseKey);
    final savedWsBaseUrl = preferences.getString(_wsBaseKey);

    final apiBaseUrl = normalizeApiBaseUrl(savedApiBaseUrl ?? ApiConfig.apiBaseUrl);
    final wsBaseUrl = normalizeWsBaseUrl(
      savedWsBaseUrl == null || savedWsBaseUrl.trim().isEmpty
          ? deriveWsBaseUrl(apiBaseUrl)
          : savedWsBaseUrl,
      apiBaseUrl: apiBaseUrl,
    );

    return ServerEndpoints(
      apiBaseUrl: apiBaseUrl,
      wsBaseUrl: wsBaseUrl,
    );
  }

  Future<ServerEndpoints> save(
    SharedPreferences preferences, {
    required String apiBaseUrl,
    String? wsBaseUrl,
  }) async {
    final normalizedApiBaseUrl = normalizeApiBaseUrl(apiBaseUrl);
    final normalizedWsBaseUrl = normalizeWsBaseUrl(
      wsBaseUrl,
      apiBaseUrl: normalizedApiBaseUrl,
    );

    await preferences.setString(_apiBaseKey, normalizedApiBaseUrl);
    await preferences.setString(_wsBaseKey, normalizedWsBaseUrl);

    return ServerEndpoints(
      apiBaseUrl: normalizedApiBaseUrl,
      wsBaseUrl: normalizedWsBaseUrl,
    );
  }

  static String normalizeApiBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return ApiConfig.apiBaseUrl;
    }

    final withScheme = trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      return ApiConfig.apiBaseUrl;
    }

    final effectivePort = uri.hasPort ? uri.port : 8080;
    final normalized = Uri(
      scheme: uri.scheme.isEmpty ? 'http' : uri.scheme,
      host: uri.host,
      port: effectivePort,
    );
    return normalized.toString();
  }

  static String normalizeWsBaseUrl(
    String? value, {
    required String apiBaseUrl,
  }) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return deriveWsBaseUrl(apiBaseUrl);
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return deriveWsBaseUrl(apiBaseUrl);
    }

    if (uri.scheme == 'ws' || uri.scheme == 'wss') {
      return uri.toString();
    }

    return deriveWsBaseUrl(trimmed);
  }

  static String deriveWsBaseUrl(String httpBase) {
    if (httpBase.startsWith('https://')) {
      return 'wss://${httpBase.substring('https://'.length)}';
    }
    if (httpBase.startsWith('http://')) {
      return 'ws://${httpBase.substring('http://'.length)}';
    }
    return httpBase;
  }
}
