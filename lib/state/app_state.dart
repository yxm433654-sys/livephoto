import 'dart:async';
import 'dart:convert';

import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/models/session.dart';
import 'package:dynamic_photo_chat_flutter/services/api_client.dart';
import 'package:dynamic_photo_chat_flutter/services/api_config.dart';
import 'package:dynamic_photo_chat_flutter/services/auth_service.dart';
import 'package:dynamic_photo_chat_flutter/services/file_service.dart';
import 'package:dynamic_photo_chat_flutter/services/message_service.dart';
import 'package:dynamic_photo_chat_flutter/services/realtime_service.dart';
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
  static const _lastMsgIdKey = 'lastMessageId';

  late ApiClient api;
  late AuthService auth;
  late MessageService messages;
  late FileService files;

  SharedPreferences? _prefs;
  Session? session;
  List<int> peers = <int>[];
  late String apiBaseUrl;
  late String wsBaseUrl;

  final Map<int, int> _unreadByPeer = <int, int>{};
  final StreamController<ChatMessage> _messageEvents =
      StreamController<ChatMessage>.broadcast();
  RealtimeService? _realtime;
  Stream<ChatMessage> get messageEvents => _messageEvents.stream;
  int _lastMessageId = 0;

  int unreadCount(int peerId) => _unreadByPeer[peerId] ?? 0;

  void clearUnread(int peerId) {
    if (!_unreadByPeer.containsKey(peerId)) return;
    _unreadByPeer.remove(peerId);
    notifyListeners();
  }

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
    _lastMessageId = _prefs!.getInt(_lastMsgIdKey) ?? 0;
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
    if (session != null) {
      _startRealtime();
    }
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final s = await auth.login(username: username, password: password);
    session = s;
    await _prefs?.setString(_sessionKey, jsonEncode(s.toJson()));
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
    _stopRealtime();
    session = null;
    await _prefs?.remove(_sessionKey);
    _unreadByPeer.clear();
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
    _unreadByPeer.remove(peerId);
    notifyListeners();
  }

  void _startRealtime() {
    final s = session;
    if (s == null) return;
    _stopRealtime();
    final rt = RealtimeService(messages, wsBaseUrl: wsBaseUrl);
    rt.start(
      userId: s.userId,
      token: s.token,
      lastMessageId: _lastMessageId,
      onMessage: (m) async {
        if (m.id > _lastMessageId) {
          _lastMessageId = m.id;
          await _prefs?.setInt(_lastMsgIdKey, _lastMessageId);
        }
        _messageEvents.add(m);

        final myId = s.userId;
        if (m.receiverId == myId) {
          await addPeer(m.senderId);
          if ((m.status ?? '').toUpperCase() != 'READ') {
            _unreadByPeer[m.senderId] = (_unreadByPeer[m.senderId] ?? 0) + 1;
            notifyListeners();
          }
        }
      },
      onError: (_) {},
    );
    _realtime = rt;
  }

  void _stopRealtime() {
    _realtime?.stop();
    _realtime = null;
  }

  @override
  void dispose() {
    _stopRealtime();
    _messageEvents.close();
    super.dispose();
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
