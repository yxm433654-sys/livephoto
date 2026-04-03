import 'dart:async';
import 'dart:io';

import 'package:vox_flutter/application/session/session_directory.dart';
import 'package:vox_flutter/models/chat_session_summary.dart';
import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/models/session.dart';
import 'package:vox_flutter/services/message/message_service.dart';
import 'package:vox_flutter/services/realtime/realtime_service.dart';
import 'package:vox_flutter/utils/user_error_message.dart';

class RealtimeConnectionCoordinator {
  RealtimeConnectionCoordinator({
    required MessageService messageService,
    required String wsBaseUrl,
  }) : _messageService = messageService,
       _wsBaseUrl = wsBaseUrl;

  final MessageService _messageService;
  final String _wsBaseUrl;

  RealtimeService? _realtime;

  void restart({
    required Session session,
    required int lastMessageId,
    required SessionDirectory sessionDirectory,
    required StreamController<ChatMessage> messageEvents,
    required Future<void> Function(int nextLastMessageId) persistLastMessageId,
    required Future<void> Function(int peerId) ensurePeer,
    required Future<void> Function() refreshSessions,
    required void Function() notifyListeners,
    required bool Function(String? notice) setConnectionNotice,
  }) {
    stop();
    final realtime = RealtimeService(_messageService, wsBaseUrl: _wsBaseUrl);
    _realtime = realtime;
    realtime.start(
      userId: session.userId,
      token: session.token,
      lastMessageId: lastMessageId,
      onMessage: (message) async {
        if (message.id > lastMessageId) {
          lastMessageId = message.id;
          await persistLastMessageId(lastMessageId);
        }
        if (setConnectionNotice(null)) {
          notifyListeners();
        }
        messageEvents.add(message);

        if (message.receiverId == session.userId) {
          await ensurePeer(message.senderId);
          if ((message.status ?? '').toUpperCase() != 'READ') {
            sessionDirectory.incrementUnread(message.senderId);
            notifyListeners();
          }
        }
      },
      onSessionUpdated: (summary) async {
        await ensurePeer(summary.peerId);
        sessionDirectory.upsertSessionSummary(summary);
        notifyListeners();
      },
      onSessionListChanged: refreshSessions,
      onMessageRead: (_) {
        notifyListeners();
      },
      onError: (_) {
        final nextNotice = UserErrorMessage.from(
          const HttpException('connection closed before full header was received'),
        );
        if (setConnectionNotice(nextNotice)) {
          notifyListeners();
        }
      },
    );
  }

  void stop() {
    _realtime?.stop();
    _realtime = null;
  }
}
