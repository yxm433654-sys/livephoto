import 'dart:io';

import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get apiBaseUrl {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) {
      return defined;
    }
    if (kIsWeb) {
      return 'http://localhost:8082';
    }
    if (Platform.isAndroid) {
      return 'http://127.0.0.1:8082';
    }
    return 'http://localhost:8082';
  }

  static String get wsBaseUrl {
    const defined = String.fromEnvironment('WS_BASE_URL');
    if (defined.isNotEmpty) {
      return defined;
    }
    final httpBase = apiBaseUrl;
    if (httpBase.startsWith('https://')) {
      return 'wss://${httpBase.substring('https://'.length)}';
    }
    if (httpBase.startsWith('http://')) {
      return 'ws://${httpBase.substring('http://'.length)}';
    }
    return httpBase;
  }
}
