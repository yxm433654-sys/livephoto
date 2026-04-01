import 'dart:async';

import 'package:vox_flutter/application/realtime/realtime_connection_coordinator.dart';
import 'package:vox_flutter/application/realtime/realtime_runtime_state.dart';
import 'package:vox_flutter/application/session/session_directory.dart';
import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/models/session.dart';
import 'package:vox_flutter/services/message/message_service.dart';

class RealtimeWorkflowCoordinator {
  RealtimeConnectionCoordinator? _connectionCoordinator;

  void start({
    required Session? session,
    required MessageService messageService,
    required String wsBaseUrl,
    required SessionDirectory sessionDirectory,
    required StreamController<ChatMessage> messageEvents,
    required RealtimeRuntimeState realtimeRuntimeState,
    required Future<void> Function() refreshSessions,
    required Future<void> Function(int peerId) ensurePeer,
    required Future<void> Function() persistLastMessageId,
    required void Function() notifyListeners,
  }) {
    if (session == null) {
      return;
    }

    stop();
    final coordinator = RealtimeConnectionCoordinator(
      messageService: messageService,
      wsBaseUrl: wsBaseUrl,
    );
    _connectionCoordinator = coordinator;
    coordinator.restart(
      session: session,
      lastMessageId: realtimeRuntimeState.lastMessageId,
      sessionDirectory: sessionDirectory,
      messageEvents: messageEvents,
      persistLastMessageId: (nextLastMessageId) async {
        if (!realtimeRuntimeState.updateLastMessageId(nextLastMessageId)) {
          return;
        }
        await persistLastMessageId();
      },
      ensurePeer: ensurePeer,
      refreshSessions: refreshSessions,
      notifyListeners: notifyListeners,
      setConnectionNotice: realtimeRuntimeState.setConnectionNotice,
    );
  }

  void stop() {
    _connectionCoordinator?.stop();
    _connectionCoordinator = null;
  }
}
