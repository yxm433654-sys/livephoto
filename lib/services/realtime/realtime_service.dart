import 'dart:async';
import 'dart:convert';

import 'package:vox_flutter/models/message.dart';
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

  void start({
    required int userId,
    required String token,
    required int lastMessageId,
    required void Function(ChatMessage message) onMessage,
    required void Function() onSessionChanged,
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
            if (type == 'NEW_MESSAGE') {
              final msg = ChatMessage.fromJson(data);
              if (msg.id > _lastMessageId) {
                _lastMessageId = msg.id;
              }
              onMessage(msg);
            } else if (type == 'SESSION_UPDATED' ||
                type == 'SESSION_LIST_CHANGED') {
              onSessionChanged();
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
            lastMessageId: _lastMessageId == 0 ? null : _lastMessageId);
        for (final m in items) {
          if (m.id > _lastMessageId) {
            _lastMessageId = m.id;
          }
          onMessage(m);
        }
      } catch (e) {
        onError(e);
      }
    });
  }

  void updateLastMessageId(int value) {
    if (value > _lastMessageId) {
      _lastMessageId = value;
    }
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
  }
}
