import 'package:vox_flutter/application/message/chat_conversation_state.dart';
import 'package:vox_flutter/application/message/chat_conversation_update.dart';
import 'package:vox_flutter/application/message/message_workflow_facade.dart';
import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/utils/user_error_message.dart';

class ConversationFlow {
  const ConversationFlow();

  static const int initialPageSize = 50;

  Future<ChatConversationState> initialize({
    required MessageWorkflowFacade workflow,
    required int currentUserId,
    required int peerId,
  }) async {
    try {
      workflow.prefetchPeer(peerId);
      final history = await workflow.loadHistory(
        userId: currentUserId,
        peerId: peerId,
        page: 0,
        size: initialPageSize,
      );
      final sorted = List<ChatMessage>.from(history)..sort(compareMessages);
      final lastMessageId =
          sorted.isEmpty ? 0 : sorted.map((e) => e.id).reduce((a, b) => a > b ? a : b);

      await markConversationRead(
        workflow: workflow,
        currentUserId: currentUserId,
        peerId: peerId,
        messages: sorted,
      );
      workflow.clearUnread(peerId);

      return ChatConversationState(
        messages: sorted,
        lastMessageId: lastMessageId,
        currentPage: 0,
        hasMore: history.length >= initialPageSize,
      );
    } catch (error) {
      return ChatConversationState(
        messages: const <ChatMessage>[],
        lastMessageId: 0,
        currentPage: 0,
        hasMore: false,
        errorMessage: UserErrorMessage.from(error),
      );
    }
  }

  Future<ChatConversationState> loadNextPage({
    required MessageWorkflowFacade workflow,
    required int currentUserId,
    required int peerId,
    required List<ChatMessage> currentMessages,
    required int currentPage,
    int pageSize = initialPageSize,
  }) async {
    final nextPage = currentPage + 1;
    final history = await workflow.loadHistory(
      userId: currentUserId,
      peerId: peerId,
      page: nextPage,
      size: pageSize,
    );

    final merged = <int, ChatMessage>{
      for (final message in currentMessages) message.id: message,
      for (final message in history) message.id: message,
    }.values.toList()
      ..sort(compareMessages);

    final lastMessageId = merged.isEmpty
        ? 0
        : merged.map((e) => e.id).reduce((a, b) => a > b ? a : b);

    return ChatConversationState(
      messages: merged,
      lastMessageId: lastMessageId,
      currentPage: nextPage,
      hasMore: history.length >= pageSize,
    );
  }

  Future<ChatConversationUpdate?> applyIncomingMessage({
    required MessageWorkflowFacade workflow,
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
    final existingIndex = nextMessages.indexWhere((item) => item.id == incomingMessage.id);
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
      nextMessages.sort(compareMessages);
    }

    if (incomingMessage.receiverId == currentUserId) {
      await markMessageRead(
        workflow: workflow,
        currentUserId: currentUserId,
        message: incomingMessage,
      );
      workflow.clearUnread(peerId);
    }

    return ChatConversationUpdate(
      messages: nextMessages,
      lastMessageId: incomingMessage.id,
      shouldScrollToBottom:
          userAtBottom || incomingMessage.senderId == currentUserId,
    );
  }

  Future<void> markConversationRead({
    required MessageWorkflowFacade workflow,
    required int currentUserId,
    required int peerId,
    required List<ChatMessage> messages,
  }) async {
    final latestUnread = messages.lastWhere(
      (message) =>
          message.receiverId == currentUserId &&
          (message.status ?? '').toUpperCase() != 'READ',
      orElse: () => ChatMessage(
        id: 0,
        senderId: 0,
        receiverId: 0,
        type: 'TEXT',
        content: null,
        resourceId: null,
        videoResourceId: null,
        coverUrl: null,
        videoUrl: null,
        media: null,
        status: 'READ',
        createdAt: null,
      ),
    );
    if (latestUnread.id <= 0) {
      return;
    }
    await markMessageRead(
      workflow: workflow,
      currentUserId: currentUserId,
      message: latestUnread,
    );
    workflow.clearUnread(peerId);
  }

  Future<void> markMessageRead({
    required MessageWorkflowFacade workflow,
    required int currentUserId,
    required ChatMessage message,
  }) async {
    if (message.receiverId != currentUserId) return;
    if ((message.status ?? '').toUpperCase() == 'READ') return;
    try {
      await workflow.markRead(message.id);
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
