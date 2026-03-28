import 'dart:convert';

import 'package:dynamic_photo_chat_flutter/models/session.dart';
import 'package:dynamic_photo_chat_flutter/services/api_client.dart';
import 'package:dynamic_photo_chat_flutter/services/api_config.dart';
import 'package:dynamic_photo_chat_flutter/services/auth_service.dart';
import 'package:dynamic_photo_chat_flutter/services/file_service.dart';
import 'package:dynamic_photo_chat_flutter/services/message_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  AppState() {
    apiBaseUrl = ApiConfig.apiBaseUrl;
    wsBaseUrl = ApiConfig.wsBaseUrl;
    _buildServices();
  }

  static const _sessionKey = 'session';
  static const _peersKey = 'peers';
  static const _apiBaseKey = 'apiBaseUrl';
  static const _wsBaseKey = 'wsBaseUrl';

  late ApiClient api;
  late AuthService auth;
  late MessageService messages;
  late FileService files;

  SharedPreferences? _prefs;
  Session? session;
  List<int> peers = <int>[];
  late String apiBaseUrl;
  late String wsBaseUrl;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final apiSaved = _prefs!.getString(_apiBaseKey);
    final wsSaved = _prefs!.getString(_wsBaseKey);
    if (apiSaved != null && apiSaved.trim().isNotEmpty) {
      apiBaseUrl = apiSaved.trim();
    }
    if (wsSaved != null && wsSaved.trim().isNotEmpty) {
      wsBaseUrl = wsSaved.trim();
    } else {
      wsBaseUrl = _deriveWsBaseUrl(apiBaseUrl);
    }
    _buildServices();
    final raw = _prefs!.getString(_sessionKey);
    if (raw != null) {
      session = Session.fromJson(jsonDecode(raw));
    }
    final peerRaw = _prefs!.getStringList(_peersKey);
    if (peerRaw != null) {
      peers = peerRaw.map((e) => int.tryParse(e)).whereType<int>().toList();
    }
    notifyListeners();
  }

  Future<void> updateEndpoints(
      {required String apiBaseUrl, String? wsBaseUrl}) async {
    this.apiBaseUrl = apiBaseUrl.trim();
    this.wsBaseUrl = (wsBaseUrl == null || wsBaseUrl.trim().isEmpty)
        ? _deriveWsBaseUrl(this.apiBaseUrl)
        : wsBaseUrl.trim();
    await _prefs?.setString(_apiBaseKey, this.apiBaseUrl);
    await _prefs?.setString(_wsBaseKey, this.wsBaseUrl);
    _buildServices();
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final s = await auth.login(username: username, password: password);
    session = s;
    await _prefs?.setString(_sessionKey, jsonEncode(s.toJson()));
    notifyListeners();
  }

  Future<void> register(String username, String password,
      {String? avatarUrl}) async {
    await auth.register(
        username: username, password: password, avatarUrl: avatarUrl);
    await login(username, password);
  }

  Future<void> logout() async {
    session = null;
    await _prefs?.remove(_sessionKey);
    notifyListeners();
  }

  Future<void> addPeer(int peerId) async {
    if (peerId <= 0) return;
    if (!peers.contains(peerId)) {
      peers = [...peers, peerId];
      await _prefs?.setStringList(
          _peersKey, peers.map((e) => e.toString()).toList());
      notifyListeners();
    }
  }

  Future<void> removePeer(int peerId) async {
    if (!peers.contains(peerId)) return;
    peers = peers.where((e) => e != peerId).toList();
    await _prefs?.setStringList(
        _peersKey, peers.map((e) => e.toString()).toList());
    notifyListeners();
  }

  void _buildServices() {
    api = ApiClient(baseUrl: apiBaseUrl);
    auth = AuthService(api);
    messages = MessageService(api);
    files = FileService(baseUrl: apiBaseUrl);
  }

  static String _deriveWsBaseUrl(String httpBase) {
    if (httpBase.startsWith('https://')) {
      return 'wss://${httpBase.substring('https://'.length)}';
    }
    if (httpBase.startsWith('http://')) {
      return 'ws://${httpBase.substring('http://'.length)}';
    }
    return httpBase;
  }
}
