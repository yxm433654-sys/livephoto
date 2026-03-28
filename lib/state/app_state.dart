import 'dart:convert';

import 'package:dynamic_photo_chat_flutter/models/session.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/services/api_client.dart';
import 'package:dynamic_photo_chat_flutter/services/api_config.dart';
import 'package:dynamic_photo_chat_flutter/services/auth_service.dart';
import 'package:dynamic_photo_chat_flutter/services/file_service.dart';
import 'package:dynamic_photo_chat_flutter/services/message_service.dart';
import 'package:dynamic_photo_chat_flutter/services/realtime_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
  Map<int, int> unreadByPeer = <int, int>{};
  Map<int, ChatMessage> lastMessageByPeer = <int, ChatMessage>{};

  RealtimeService? _realtime;

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

    final selected = await _autoSelectApiBaseUrl(initial: apiBaseUrl);
    if (selected != apiBaseUrl) {
      apiBaseUrl = selected;
      wsBaseUrl = _deriveWsBaseUrl(apiBaseUrl);
      await _prefs?.setString(_apiBaseKey, apiBaseUrl);
      await _prefs?.setString(_wsBaseKey, wsBaseUrl);
      _buildServices();
    }

    final raw = _prefs!.getString(_sessionKey);
    if (raw != null) {
      session = Session.fromJson(jsonDecode(raw));
    }
    final peerRaw = _prefs!.getStringList(_peersKey);
    if (peerRaw != null) {
      peers = peerRaw.map((e) => int.tryParse(e)).whereType<int>().toList();
    }

    if (session != null) {
      _startRealtime();
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
    unreadByPeer = <int, int>{};
    lastMessageByPeer = <int, ChatMessage>{};
    _startRealtime();
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
    _stopRealtime();
    unreadByPeer = <int, int>{};
    lastMessageByPeer = <int, ChatMessage>{};
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
    unreadByPeer = Map.of(unreadByPeer)..remove(peerId);
    lastMessageByPeer = Map.of(lastMessageByPeer)..remove(peerId);
    notifyListeners();
  }

  Future<void> markPeerRead(int peerId) async {
    if (!unreadByPeer.containsKey(peerId) || unreadByPeer[peerId] == 0) return;
    unreadByPeer = Map.of(unreadByPeer)..[peerId] = 0;
    notifyListeners();
  }

  void recordLocalMessage(ChatMessage message) {
    final s = session;
    if (s == null) return;
    final myId = s.userId;
    final peerId = message.senderId == myId ? message.receiverId : message.senderId;
    lastMessageByPeer = Map.of(lastMessageByPeer)..[peerId] = message;
    notifyListeners();
  }

  void _buildServices() {
    api = ApiClient(baseUrl: apiBaseUrl);
    auth = AuthService(api);
    messages = MessageService(api);
    files = FileService(baseUrl: apiBaseUrl);
  }

  Future<bool> testApiConnection([String? baseUrl]) async {
    return _checkHealth(baseUrl ?? apiBaseUrl);
  }

  Future<String> _autoSelectApiBaseUrl({required String initial}) async {
    final candidates = <String>[
      initial,
    ];

    if (defaultTargetPlatform == TargetPlatform.android) {
      candidates.addAll([
        'http://127.0.0.1:8082',
        'http://10.0.2.2:8082',
        'http://localhost:8082',
      ]);
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      candidates.addAll([
        'http://localhost:8082',
        'http://127.0.0.1:8082',
      ]);
    } else {
      candidates.add('http://localhost:8082');
    }

    final dedup = <String>{};
    final ordered = <String>[];
    for (final c in candidates) {
      final normalized = c.trim();
      if (normalized.isEmpty) continue;
      if (dedup.add(normalized)) ordered.add(normalized);
    }

    for (final baseUrl in ordered) {
      if (await _checkHealth(baseUrl)) {
        return baseUrl;
      }
    }

    return initial;
  }

  Future<bool> _checkHealth(String baseUrl) async {
    try {
      final uri = Uri.parse(baseUrl).replace(path: '/actuator/health');
      final res = await http.get(uri).timeout(const Duration(milliseconds: 1200));
      if (res.statusCode != 200) return false;
      return res.body.contains('UP');
    } catch (_) {
      return false;
    }
  }

  void _startRealtime() {
    final s = session;
    if (s == null) return;
    _stopRealtime();

    final rt = RealtimeService(messages, wsBaseUrl: wsBaseUrl);
    _realtime = rt;
    rt.start(
      userId: s.userId,
      token: s.token,
      lastMessageId: 0,
      onMessage: (m) {
        _handleIncomingMessage(m);
      },
      onError: (_) {},
    );
  }

  void _stopRealtime() {
    _realtime?.stop();
    _realtime = null;
  }

  void _handleIncomingMessage(ChatMessage m) {
    final s = session;
    if (s == null) return;
    final myId = s.userId;
    final peerId = m.senderId == myId ? m.receiverId : m.senderId;

    if (!peers.contains(peerId)) {
      peers = [...peers, peerId];
      _prefs?.setStringList(_peersKey, peers.map((e) => e.toString()).toList());
    }

    lastMessageByPeer = Map.of(lastMessageByPeer)..[peerId] = m;
    if (m.receiverId == myId) {
      final prev = unreadByPeer[peerId] ?? 0;
      unreadByPeer = Map.of(unreadByPeer)..[peerId] = prev + 1;
    }
    notifyListeners();
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
