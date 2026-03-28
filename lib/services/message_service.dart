import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/services/api_client.dart';

class MessageService {
  MessageService(this._api);

  final ApiClient _api;

  Future<int> sendText({
    required int senderId,
    required int receiverId,
    required String content,
  }) async {
    final res = await _api.postJson<Object?>(
      '/api/message/send',
      body: {
        'senderId': senderId,
        'receiverId': receiverId,
        'type': 'TEXT',
        'content': content,
      },
      decode: (raw) => raw,
    );
    if (!res.success || res.data is! Map) {
      throw Exception(res.message ?? 'Send failed');
    }
    return ((res.data as Map)['messageId'] as num).toInt();
  }

  Future<int> sendImage({
    required int senderId,
    required int receiverId,
    required int resourceId,
  }) async {
    final res = await _api.postJson<Object?>(
      '/api/message/send',
      body: {
        'senderId': senderId,
        'receiverId': receiverId,
        'type': 'IMAGE',
        'resourceId': resourceId,
      },
      decode: (raw) => raw,
    );
    if (!res.success || res.data is! Map) {
      throw Exception(res.message ?? 'Send failed');
    }
    return ((res.data as Map)['messageId'] as num).toInt();
  }

  Future<int> sendVideo({
    required int senderId,
    required int receiverId,
    required int videoResourceId,
  }) async {
    final res = await _api.postJson<Object?>(
      '/api/message/send',
      body: {
        'senderId': senderId,
        'receiverId': receiverId,
        'type': 'VIDEO',
        'videoResourceId': videoResourceId,
      },
      decode: (raw) => raw,
    );
    if (!res.success || res.data is! Map) {
      throw Exception(res.message ?? 'Send failed');
    }
    return ((res.data as Map)['messageId'] as num).toInt();
  }

  Future<int> sendDynamicPhoto({
    required int senderId,
    required int receiverId,
    required int coverId,
    required int videoId,
  }) async {
    final res = await _api.postJson<Object?>(
      '/api/message/send',
      body: {
        'senderId': senderId,
        'receiverId': receiverId,
        'type': 'DYNAMIC_PHOTO',
        'resourceId': coverId,
        'videoResourceId': videoId,
      },
      decode: (raw) => raw,
    );
    if (!res.success || res.data is! Map) {
      throw Exception(res.message ?? 'Send failed');
    }
    return ((res.data as Map)['messageId'] as num).toInt();
  }

  Future<List<ChatMessage>> poll({
    required int userId,
    int? lastMessageId,
  }) async {
    final query = <String, String>{'userId': userId.toString()};
    if (lastMessageId != null) {
      query['lastMessageId'] = lastMessageId.toString();
    }
    final res = await _api.get<List<ChatMessage>>(
      '/api/message/poll',
      query: query,
      decode: (raw) {
        if (raw is! List) return <ChatMessage>[];
        return raw.map(ChatMessage.fromJson).toList();
      },
    );
    if (!res.success) {
      throw Exception(res.message ?? 'Poll failed');
    }
    return res.data ?? <ChatMessage>[];
  }

  Future<List<ChatMessage>> history({
    required int userId,
    required int peerId,
    int page = 0,
    int size = 50,
  }) async {
    final res = await _api.get<Object?>(
      '/api/message/history',
      query: {
        'userId': userId.toString(),
        'peerId': peerId.toString(),
        'page': page.toString(),
        'size': size.toString(),
      },
      decode: (raw) => raw,
    );
    if (!res.success) {
      throw Exception(res.message ?? 'History failed');
    }
    if (res.data is! Map) return <ChatMessage>[];
    final data = res.data as Map;
    final items = data['data'];
    if (items is! List) return <ChatMessage>[];
    final messages = items.map(ChatMessage.fromJson).toList();
    messages.sort((a, b) => a.id.compareTo(b.id));
    return messages;
  }

  Future<void> markRead(int messageId) async {
    final res = await _api.putJson<Object?>(
      '/api/message/read/$messageId',
      decode: (raw) => raw,
    );
    if (!res.success) {
      throw Exception(res.message ?? 'Mark read failed');
    }
  }
}
