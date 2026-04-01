import 'package:dynamic_photo_chat_flutter/application/message/chat_conversation_state.dart';
import 'package:dynamic_photo_chat_flutter/application/message/chat_conversation_update.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/utils/user_error_message.dart';

class ChatConversationCoordinator {
  const ChatConversationCoordinator();

  Future<ChatConversationState> initialize({
    required AppState appState,
    required int currentUserId,
    required int peerId,
  }) async {
    try {
      appState.prefetchUser(peerId);
      final history = await appState.messages.history(
        userId: currentUserId,
        peerId: peerId,
        page: 0,
        size: 100,
      );
      final sorted = List<ChatMessage>.from(history)..sort(compareMessages);
      final lastMessageId = sorted.isEmpty
          ? 0
          : sorted.map((e) => e.id).reduce((a, b) => a > b ? a : b);

      await markAllRead(
        appState: appState,
        currentUserId: currentUserId,
        messages: sorted,
      );
      appState.clearUnread(peerId);

      return ChatConversationState(
        messages: sorted,
        lastMessageId: lastMessageId,
      );
    } catch (error) {
      return ChatConversationState(
        messages: const <ChatMessage>[],
        lastMessageId: 0,
        errorMessage: UserErrorMessage.from(error),
      );
    }
  }

  Future<ChatConversationUpdate?> applyIncomingMessage({
    required AppState appState,
    required List<ChatMessage> currentMessages,
    required ChatMessage incomingMessage,
    required int currentUserId,
    required int peerId,
    required bool userAtBottom,
  }) async {
    if (!isInThisChat(
      message: incomingMessage,
      currentUserId: currentUserId,
      peerId: peerId,
    )) {
      return null;
    }

    final nextMessages = List<ChatMessage>.from(currentMessages);
    final existingIndex =
        nextMessages.indexWhere((item) => item.id == incomingMessage.id);
    final pendingIndex = existingIndex < 0
        ? findPendingLocalIndex(
            nextMessages,
            incomingMessage,
            currentUserId,
            peerId,
          )
        : -1;

    if (existingIndex >= 0) {
      nextMessages[existingIndex] = incomingMessage;
    } else if (pendingIndex >= 0) {
      nextMessages[pendingIndex] = incomingMessage;
    } else {
      nextMessages.add(incomingMessage);
    }

    nextMessages.sort(compareMessages);

    if (incomingMessage.receiverId == currentUserId) {
      await markMessageRead(
        appState: appState,
        currentUserId: currentUserId,
        message: incomingMessage,
      );
      appState.clearUnread(peerId);
    }

    return ChatConversationUpdate(
      messages: nextMessages,
      lastMessageId: incomingMessage.id,
      shouldScrollToBottom:
          userAtBottom || incomingMessage.senderId == currentUserId,
    );
  }

  Future<void> markAllRead({
    required AppState appState,
    required int currentUserId,
    required List<ChatMessage> messages,
  }) async {
    for (final message in messages) {
      await markMessageRead(
        appState: appState,
        currentUserId: currentUserId,
        message: message,
      );
    }
  }

  Future<void> markMessageRead({
    required AppState appState,
    required int currentUserId,
    required ChatMessage message,
  }) async {
    if (message.receiverId != currentUserId) return;
    if ((message.status ?? '').toUpperCase() == 'READ') return;
    try {
      await appState.messages.markRead(message.id);
    } catch (_) {}
  }

  bool isInThisChat({
    required ChatMessage message,
    required int currentUserId,
    required int peerId,
  }) {
    final fromPeer =
        message.senderId == peerId && message.receiverId == currentUserId;
    final fromMe =
        message.senderId == currentUserId && message.receiverId == peerId;
    return fromPeer || fromMe;
  }

  int findPendingLocalIndex(
    List<ChatMessage> messages,
    ChatMessage incomingMessage,
    int currentUserId,
    int peerId,
  ) {
    if (incomingMessage.senderId != currentUserId) return -1;
    return messages.indexWhere(
      (candidate) =>
          candidate.id < 0 &&
          candidate.senderId == currentUserId &&
          candidate.receiverId == peerId &&
          candidate.type == incomingMessage.type &&
          (candidate.status ?? '').toUpperCase() == 'SENDING',
    );
  }

  int compareMessages(ChatMessage a, ChatMessage b) {
    final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
    if (aTime != bTime) {
      return aTime.compareTo(bTime);
    }
    final aTemp = a.id < 0;
    final bTemp = b.id < 0;
    if (aTemp != bTemp) {
      return aTemp ? 1 : -1;
    }
    return a.id.compareTo(b.id);
  }
}
