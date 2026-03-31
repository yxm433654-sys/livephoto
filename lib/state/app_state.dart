import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/models/session.dart';
import 'package:dynamic_photo_chat_flutter/models/user.dart';
import 'package:dynamic_photo_chat_flutter/services/api_client.dart';
import 'package:dynamic_photo_chat_flutter/services/api_config.dart';
import 'package:dynamic_photo_chat_flutter/services/auth_service.dart';
import 'package:dynamic_photo_chat_flutter/services/file_service.dart';
import 'package:dynamic_photo_chat_flutter/services/message_service.dart';
import 'package:dynamic_photo_chat_flutter/services/realtime_service.dart';
import 'package:dynamic_photo_chat_flutter/utils/user_error_message.dart';
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
  final Map<int, UserProfile> _userCache = <int, UserProfile>{};
  final Map<int, Future<UserProfile?>> _userFetches =
      <int, Future<UserProfile?>>{};
  final StreamController<ChatMessage> _messageEvents =
      StreamController<ChatMessage>.broadcast();
  RealtimeService? _realtime;
  Stream<ChatMessage> get messageEvents => _messageEvents.stream;
  int _lastMessageId = 0;
  String? connectionNotice;

  int unreadCount(int peerId) => _unreadByPeer[peerId] ?? 0;

  String displayNameFor(int userId) {
    final cached = _userCache[userId];
    final name = cached?.username.trim();
    if (name != null && name.isNotEmpty) return name;
    return '用户 $userId';
  }

  String? avatarUrlFor(int userId) {
    final url = _userCache[userId]?.avatarUrl;
    if (url == null) return null;
    final v = url.trim();
    if (v.isEmpty) return null;
    final parsed = Uri.tryParse(v);
    if (parsed != null && parsed.hasScheme) return v;
    final base = Uri.parse(apiBaseUrl);
    final path = v.startsWith('/') ? v : '/$v';
    return base.replace(path: path, query: null, fragment: null).toString();
  }

  Future<UserProfile?> prefetchUser(int userId) {
    if (userId <= 0) return Future<UserProfile?>.value(null);
    final cached = _userCache[userId];
    if (cached != null) return Future<UserProfile?>.value(cached);
    final existing = _userFetches[userId];
    if (existing != null) return existing;

    final future = () async {
      try {
        final profile = await auth.getUser(userId);
        _userCache[userId] = profile;
        notifyListeners();
        return profile;
      } catch (_) {
        return null;
      } finally {
        _userFetches.remove(userId);
      }
    }();

    _userFetches[userId] = future;
    return future;
  }

  Future<UserProfile?> findUserByUsername(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return null;
    for (final user in _userCache.values) {
      if (user.username == trimmed) {
        return user;
      }
    }
    try {
      final user = await auth.getUserByUsername(trimmed);
      _userCache[user.userId] = user;
      notifyListeners();
      return user;
    } catch (_) {
      return null;
    }
  }

  void clearUnread(int peerId) {
    if (!_unreadByPeer.containsKey(peerId)) return;
    _unreadByPeer.remove(peerId);
    notifyListeners();
  }

  void clearConnectionNotice() {
    if (connectionNotice == null) return;
    connectionNotice = null;
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

    await _restoreSessionScopedState();
    if (session != null) {
      _startRealtime();
    }
    notifyListeners();
  }

  Future<void> updateEndpoints({
    required String apiBaseUrl,
    String? wsBaseUrl,
  }) async {
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
    final nextSession = await auth.login(username: username, password: password);
    _stopRealtime();
    session = nextSession;
    await _prefs?.setString(_sessionKey, jsonEncode(nextSession.toJson()));
    await _restoreSessionScopedState();
    _startRealtime();
    notifyListeners();
  }

  Future<void> register(
    String username,
    String password, {
    String? avatarUrl,
  }) async {
    await auth.register(
      username: username,
      password: password,
      avatarUrl: avatarUrl,
    );
    await login(username, password);
  }

  Future<void> logout() async {
    _stopRealtime();
    session = null;
    peers = <int>[];
    _lastMessageId = 0;
    connectionNotice = null;
    await _prefs?.remove(_sessionKey);
    _unreadByPeer.clear();
    _userCache.clear();
    _userFetches.clear();
    notifyListeners();
  }

  Future<void> addPeer(int peerId) async {
    if (peerId <= 0) return;
    if (!peers.contains(peerId)) {
      peers = [...peers, peerId];
      await _savePeers();
      notifyListeners();
    }
  }

  Future<void> removePeer(int peerId) async {
    if (!peers.contains(peerId)) return;
    peers = peers.where((e) => e != peerId).toList();
    await _savePeers();
    _unreadByPeer.remove(peerId);
    notifyListeners();
  }

  void _startRealtime() {
    final currentSession = session;
    if (currentSession == null) return;

    _stopRealtime();
    final rt = RealtimeService(messages, wsBaseUrl: wsBaseUrl);
    rt.start(
      userId: currentSession.userId,
      token: currentSession.token,
      lastMessageId: _lastMessageId,
      onMessage: (message) async {
        if (message.id > _lastMessageId) {
          _lastMessageId = message.id;
          await _saveLastMessageId();
        }
        if (connectionNotice != null) {
          connectionNotice = null;
          notifyListeners();
        }
        _messageEvents.add(message);

        final myId = currentSession.userId;
        if (message.receiverId == myId) {
          await addPeer(message.senderId);
          if ((message.status ?? '').toUpperCase() != 'READ') {
            _unreadByPeer[message.senderId] =
                (_unreadByPeer[message.senderId] ?? 0) + 1;
            notifyListeners();
          }
        }
      },
      onError: (_) {
        final nextNotice = UserErrorMessage.from(
          const HttpException('connection closed before full header was received'),
        );
        if (connectionNotice == nextNotice) {
          return;
        }
        connectionNotice = nextNotice;
        notifyListeners();
      },
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

  Future<void> _restoreSessionScopedState() async {
    peers = <int>[];
    _lastMessageId = 0;
    _unreadByPeer.clear();
    final peerRaw = _prefs?.getStringList(_scopedKey(_peersKey));
    if (peerRaw != null) {
      peers = peerRaw.map((e) => int.tryParse(e)).whereType<int>().toList();
    }
    _lastMessageId = _prefs?.getInt(_scopedKey(_lastMsgIdKey)) ?? 0;
  }

  Future<void> _savePeers() async {
    await _prefs?.setStringList(
      _scopedKey(_peersKey),
      peers.map((e) => e.toString()).toList(),
    );
  }

  Future<void> _saveLastMessageId() async {
    await _prefs?.setInt(_scopedKey(_lastMsgIdKey), _lastMessageId);
  }

  String _scopedKey(String base) {
    final userId = session?.userId;
    return userId == null ? base : '${base}_$userId';
  }
}
