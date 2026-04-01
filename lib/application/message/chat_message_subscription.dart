import 'dart:async';

import 'package:vox_flutter/application/message/conversation_flow.dart';
import 'package:vox_flutter/application/message/chat_conversation_update.dart';
import 'package:vox_flutter/application/message/message_workflow_facade.dart';
import 'package:vox_flutter/models/message.dart';

class ChatMessageSubscription {
  const ChatMessageSubscription({
    this.coordinator = const ConversationFlow(),
  });

  final ConversationFlow coordinator;

  StreamSubscription<ChatMessage> bind({
    required MessageWorkflowFacade workflow,
    required int currentUserId,
    required int peerId,
    required List<ChatMessage> currentMessages,
    required bool Function() isUserAtBottom,
    required void Function(ChatMessage incomingMessage, int? replacedTempId)
        onBeforeApply,
    required void Function(ChatConversationSubscriptionUpdate update) onUpdate,
  }) {
    return workflow.messageEvents.listen((incomingMessage) async {
      final pendingIndex = coordinator.findPendingLocalIndex(
        currentMessages,
        incomingMessage,
        currentUserId,
        peerId,
      );
      final replacedTempId =
          pendingIndex >= 0 ? currentMessages[pendingIndex].id : null;

      final update = await coordinator.applyIncomingMessage(
        workflow: workflow,
        currentMessages: currentMessages,
        incomingMessage: incomingMessage,
        currentUserId: currentUserId,
        peerId: peerId,
        userAtBottom: isUserAtBottom(),
      );
      if (update == null) {
        return;
      }

      onBeforeApply(incomingMessage, replacedTempId);
      onUpdate(
        ChatConversationSubscriptionUpdate(
          incomingMessage: incomingMessage,
          replacedTempId: replacedTempId,
          conversationUpdate: update,
        ),
      );
    });
  }
}

class ChatConversationSubscriptionUpdate {
  const ChatConversationSubscriptionUpdate({
    required this.incomingMessage,
    required this.replacedTempId,
    required this.conversationUpdate,
  });

  final ChatMessage incomingMessage;
  final int? replacedTempId;
  final ChatConversationUpdate conversationUpdate;
}

