import 'dart:async';
import 'dart:convert';

import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/models/chat_session_summary.dart';
import 'package:vox_flutter/services/message/message_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RealtimeService {
  RealtimeService(this._messageService, {required String wsBaseUrl})
      : _wsBaseUrl = wsBaseUrl;

  final MessageService _messageService;
  final String _wsBaseUrl;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _pollTimer;
  int _lastMessageId = 0;
  final Map<int, String> _messageFingerprints = <int, String>{};

  void start({
    required int userId,
    required String token,
    required int lastMessageId,
    required void Function(ChatMessage message) onMessage,
    required void Function(ChatSessionSummary summary) onSessionUpdated,
    required void Function() onSessionListChanged,
    required void Function(int messageId) onMessageRead,
    required void Function(Object error) onError,
  }) {
    stop();
    _lastMessageId = lastMessageId;

    final wsUrl =
        '$_wsBaseUrl/ws/chat?userId=$userId&token=${Uri.encodeQueryComponent(token)}';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSub = _channel!.stream.listen(
        (event) {
          try {
            if (event is! String) return;
            final obj = jsonDecode(event);
            if (obj is! Map) return;
            final type = obj['type']?.toString();
            final data = obj['data'];
            switch (type) {
              case 'NEW_MESSAGE':
                final msg = ChatMessage.fromJson(data);
                _ingestMessage(msg, onMessage);
              case 'SESSION_UPDATED':
                final summary = ChatSessionSummary.fromJson(data);
                if (summary != null) {
                  onSessionUpdated(summary);
                }
              case 'SESSION_LIST_CHANGED':
                onSessionListChanged();
              case 'READ_RECEIPT':
                // Server tells us one of our sent messages was read.
                final messageId = data is Map ? data['messageId'] : null;
                if (messageId is int) {
                  onMessageRead(messageId);
                } else if (messageId is num) {
                  onMessageRead(messageId.toInt());
                }
            }
          } catch (e) {
            onError(e);
          }
        },
        onError: (e) => onError(e),
        cancelOnError: false,
      );
    } catch (e) {
      onError(e);
    }

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final items = await _messageService.poll(
          userId: userId,
          lastMessageId: _lastMessageId == 0 ? null : _lastMessageId,
        );
        for (final message in items) {
          _ingestMessage(message, onMessage);
        }
      } catch (e) {
        onError(e);
      }
    });
  }

  void updateLastMessageId(int value) {
    if (value > _lastMessageId) _lastMessageId = value;
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    _messageFingerprints.clear();
  }

  void _ingestMessage(
    ChatMessage message,
    void Function(ChatMessage message) onMessage,
  ) {
    if (message.id > _lastMessageId) _lastMessageId = message.id;

    final fingerprint = jsonEncode(message.toJson());
    final previous = _messageFingerprints[message.id];
    if (previous == fingerprint) return;

    _messageFingerprints[message.id] = fingerprint;
    if (_messageFingerprints.length > 500) {
      final staleKeys = _messageFingerprints.keys.toList()
        ..sort((a, b) => a.compareTo(b));
      for (final key in staleKeys.take(_messageFingerprints.length - 400)) {
        _messageFingerprints.remove(key);
      }
    }

    onMessage(message);
  }
}
