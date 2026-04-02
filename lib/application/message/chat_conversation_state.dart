import 'package:vox_flutter/models/message.dart';

class ChatConversationState {
  const ChatConversationState({
    required this.messages,
    required this.lastMessageId,
    required this.currentPage,
    required this.hasMore,
    this.errorMessage,
  });

  final List<ChatMessage> messages;
  final int lastMessageId;
  final int currentPage;
  final bool hasMore;
  final String? errorMessage;
}
