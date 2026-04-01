import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vox_flutter/application/session/account_flow.dart';
import 'package:vox_flutter/application/realtime/realtime_workflow_coordinator.dart';
import 'package:vox_flutter/application/session/service_bundle_factory.dart';
import 'package:vox_flutter/application/session/session_lifecycle.dart';
import 'package:vox_flutter/application/realtime/realtime_runtime_state.dart';
import 'package:vox_flutter/application/session/session_directory.dart';
import 'package:vox_flutter/application/session/session_directory_flow.dart';
import 'package:vox_flutter/application/session/session_scope_store.dart';
import 'package:vox_flutter/application/session/session_persistence.dart';
import 'package:vox_flutter/models/chat_session_summary.dart';
import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/models/session.dart';
import 'package:vox_flutter/models/user.dart';
import 'package:vox_flutter/services/network/api_client.dart';
import 'package:vox_flutter/services/network/api_config.dart';
import 'package:vox_flutter/services/auth/auth_service.dart';
import 'package:vox_flutter/services/attachment/attachment_service.dart';
import 'package:vox_flutter/services/message/message_service.dart';
import 'package:vox_flutter/services/network/server_config_store.dart';
import 'package:vox_flutter/services/session/session_service.dart';

class AppState extends ChangeNotifier {
  AppState() {
    apiBaseUrl = ApiConfig.apiBaseUrl;
    wsBaseUrl = ApiConfig.wsBaseUrl;
    _buildServices();
  }

  late ApiClient api;
  late AuthService auth;
  late MessageService messages;
  late SessionService sessions;
  late AttachmentService attachments;

  SharedPreferences? _prefs;
  Session? session;
  late String apiBaseUrl;
  late String wsBaseUrl;
  final ServerConfigStore _serverConfigStore = ServerConfigStore();
  final SessionDirectory _sessionDirectory = SessionDirectory();
  final AccountFlow _accountFlow =
      const AccountFlow();
  final ServiceBundleFactory _bundleFactory =
      const ServiceBundleFactory();
  final SessionLifecycle _sessionLifecycle =
      const SessionLifecycle();
  final SessionDirectoryFlow _sessionDirectoryCoordinator =
      const SessionDirectoryFlow();
  final SessionPersistence _sessionPersistence =
      const SessionPersistence();
  final SessionScopeStore _sessionScopeStore = const SessionScopeStore();

  final StreamController<ChatMessage> _messageEvents =
      StreamController<ChatMessage>.broadcast();
  final RealtimeWorkflowCoordinator _realtimeWorkflowCoordinator =
      RealtimeWorkflowCoordinator();
  final RealtimeRuntimeState _realtimeRuntimeState = RealtimeRuntimeState();
  Stream<ChatMessage> get messageEvents => _messageEvents.stream;
  String? get connectionNotice => _realtimeRuntimeState.connectionNotice;

  List<int> get peers => _sessionDirectory.peers;
  List<ChatSessionSummary> get conversationSummaries =>
      _sessionDirectory.conversationSummaries;

  int unreadCount(int peerId) => _sessionDirectory.unreadCount(peerId);

  List<int> orderedPeerIds() => _sessionDirectory.orderedPeerIds();

  ChatSessionSummary? sessionSummaryFor(int peerId) =>
      _sessionDirectory.sessionSummaryFor(peerId);

  String displayNameFor(int userId) => _sessionDirectory.displayNameFor(userId);

  String? avatarUrlFor(int userId) =>
      _sessionDirectory.avatarUrlFor(userId, apiBaseUrl);

  Future<UserProfile?> prefetchUser(int userId) {
    return _sessionDirectoryCoordinator.prefetchUser(
      userId: userId,
      authService: auth,
      sessionDirectory: _sessionDirectory,
      notifyListeners: notifyListeners,
    );
  }

  Future<UserProfile?> findUserByUsername(String username) async {
    return _sessionDirectoryCoordinator.findUserByUsername(
      username: username,
      authService: auth,
      sessionDirectory: _sessionDirectory,
      notifyListeners: notifyListeners,
    );
  }

  void clearUnread(int peerId) {
    _sessionDirectoryCoordinator.clearUnread(
      peerId: peerId,
      sessionDirectory: _sessionDirectory,
      notifyListeners: notifyListeners,
    );
  }

  void clearConnectionNotice() {
    if (connectionNotice == null) return;
    _realtimeRuntimeState.clearConnectionNotice();
    notifyListeners();
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final bootstrapResult = await _accountFlow.initialize(
      preferences: _prefs!,
      serverConfigStore: _serverConfigStore,
      rebuildServices: _rebuildServices,
      syncSignedInState: _syncSignedInState,
    );
    apiBaseUrl = bootstrapResult.apiBaseUrl;
    wsBaseUrl = bootstrapResult.wsBaseUrl;
    session = bootstrapResult.session;
    notifyListeners();
  }

  Future<void> updateEndpoints({
    required String apiBaseUrl,
    String? wsBaseUrl,
  }) async {
    final result = await _accountFlow.updateEndpoints(
      preferences: _prefs,
      apiBaseUrl: apiBaseUrl,
      wsBaseUrl: wsBaseUrl,
      session: session,
      serverConfigStore: _serverConfigStore,
      rebuildServices: _rebuildServices,
      syncSignedInState: _syncSignedInState,
    );
    if (result == null) return;
    this.apiBaseUrl = result.apiBaseUrl;
    this.wsBaseUrl = result.wsBaseUrl;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final nextSession = await _accountFlow.login(
      username: username,
      password: password,
      authService: auth,
      stopRealtime: () async => _stopRealtime(),
      persistSession: (next) =>
          _sessionLifecycle.persistSession(_prefs, next),
      syncSignedInState: _syncSignedInState,
    );
    session = nextSession;
    notifyListeners();
  }

  Future<void> register(
    String username,
    String password, {
    String? avatarUrl,
  }) async {
    await _accountFlow.register(
      username: username,
      password: password,
      avatarUrl: avatarUrl,
      authService: auth,
      login: login,
    );
  }

  Future<void> logout() async {
    session = null;
    await _accountFlow.logout(
      clearSignedOutState: () => _sessionLifecycle.clearSignedOutState(
        preferences: _prefs,
        stopRealtime: () async => _stopRealtime(),
        clearSessionDirectory: _sessionDirectory.clearAll,
        clearConnectionNotice: _realtimeRuntimeState.clearConnectionNotice,
        resetLastMessageId: _realtimeRuntimeState.resetLastMessageId,
      ),
    );
    notifyListeners();
  }

  Future<void> addPeer(int peerId) async {
    await _sessionDirectoryCoordinator.addPeer(
      peerId: peerId,
      sessionDirectory: _sessionDirectory,
      persistPeers: _savePeers,
      notifyListeners: notifyListeners,
    );
  }

  Future<void> removePeer(int peerId) async {
    await _sessionDirectoryCoordinator.removePeer(
      peerId: peerId,
      sessionDirectory: _sessionDirectory,
      persistPeers: _savePeers,
      notifyListeners: notifyListeners,
    );
  }

  Future<void> refreshSessions({bool notify = true}) async {
    await _sessionDirectoryCoordinator.refreshSessions(
      session: session,
      sessionService: sessions,
      sessionDirectory: _sessionDirectory,
      notifyListeners: notifyListeners,
      notify: notify,
    );
  }

  void _startRealtime() {
    _realtimeWorkflowCoordinator.start(
      session: session,
      messageService: messages,
      wsBaseUrl: wsBaseUrl,
      sessionDirectory: _sessionDirectory,
      messageEvents: _messageEvents,
      realtimeRuntimeState: _realtimeRuntimeState,
      persistLastMessageId: _saveLastMessageId,
      ensurePeer: addPeer,
      refreshSessions: () => refreshSessions(),
      notifyListeners: notifyListeners,
    );
  }

  void _stopRealtime() {
    _realtimeWorkflowCoordinator.stop();
  }

  @override
  void dispose() {
    _stopRealtime();
    _messageEvents.close();
    super.dispose();
  }

  void _buildServices() {
    final bundle = _bundleFactory.build(apiBaseUrl: apiBaseUrl);
    api = bundle.apiClient;
    auth = bundle.authService;
    messages = bundle.messageService;
    sessions = bundle.sessionService;
    attachments = bundle.attachmentService;
  }

  Future<void> _rebuildServices(String nextApiBaseUrl, String nextWsBaseUrl) async {
    apiBaseUrl = nextApiBaseUrl;
    wsBaseUrl = nextWsBaseUrl;
    _buildServices();
  }

  Future<void> _syncSignedInState(Session? nextSession) async {
    session = nextSession;
    await _sessionLifecycle.syncSignedInState(
      session: session,
      restoreScopedState: _restoreSessionScopedState,
      refreshSessions: refreshSessions,
      startRealtime: _startRealtime,
    );
  }

  Future<void> _restoreSessionScopedState() async {
    await _sessionPersistence.restoreScopedState(
      preferences: _prefs,
      session: session,
      sessionDirectory: _sessionDirectory,
      sessionScopeStore: _sessionScopeStore,
      realtimeRuntimeState: _realtimeRuntimeState,
    );
  }

  Future<void> _savePeers() async {
    await _sessionPersistence.savePeers(
      preferences: _prefs,
      session: session,
      sessionDirectory: _sessionDirectory,
      sessionScopeStore: _sessionScopeStore,
    );
  }

  Future<void> _saveLastMessageId() async {
    await _sessionPersistence.saveLastMessageId(
      preferences: _prefs,
      session: session,
      sessionScopeStore: _sessionScopeStore,
      realtimeRuntimeState: _realtimeRuntimeState,
    );
  }
}




