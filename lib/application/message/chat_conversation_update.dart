import 'package:dynamic_photo_chat_flutter/models/message.dart';

class ChatConversationUpdate {
  const ChatConversationUpdate({
    required this.messages,
    required this.lastMessageId,
    required this.shouldScrollToBottom,
  });

  final List<ChatMessage> messages;
  final int lastMessageId;
  final bool shouldScrollToBottom;
}
