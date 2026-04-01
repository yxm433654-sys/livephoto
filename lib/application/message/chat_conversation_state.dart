import 'package:dynamic_photo_chat_flutter/models/message.dart';

class ChatConversationState {
  const ChatConversationState({
    required this.messages,
    required this.lastMessageId,
    this.errorMessage,
  });

  final List<ChatMessage> messages;
  final int lastMessageId;
  final String? errorMessage;
}
