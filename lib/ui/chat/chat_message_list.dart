import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vox_flutter/application/message/media_url_resolver.dart';
import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/ui/widgets/message_bubble.dart';

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.loading,
    required this.scrollController,
    required this.messages,
    required this.myId,
    required this.myName,
    required this.peerName,
    required this.myAvatarUrl,
    required this.peerAvatarUrl,
    required this.shouldShowTimestamp,
    required this.formatTimestamp,
    required this.onPlayVideo,
    required this.onPreviewImage,
    required this.onOpenDynamicPhoto,
    required this.localCoverBytesByMessageId,
    required this.localCoverPathByMessageId,
    required this.urlResolver,
    required this.onRetryMessage,
    required this.onOpenFileMessage,
    required this.onShowMessageActions,
  });

  final bool loading;
  final ScrollController scrollController;
  final List<ChatMessage> messages;
  final int myId;
  final String myName;
  final String peerName;
  final String? myAvatarUrl;
  final String? peerAvatarUrl;
  final bool Function(int index) shouldShowTimestamp;
  final String Function(DateTime? time) formatTimestamp;
  final void Function(String url) onPlayVideo;
  final void Function(String url) onPreviewImage;
  final Future<void> Function(String coverUrl, String videoUrl, double aspectRatio)
      onOpenDynamicPhoto;
  final Map<int, Uint8List> localCoverBytesByMessageId;
  final Map<int, String> localCoverPathByMessageId;
  final MediaUrlResolver urlResolver;
  final void Function(ChatMessage message) onRetryMessage;
  final Future<void> Function(ChatMessage message) onOpenFileMessage;
  final Future<void> Function(ChatMessage message) onShowMessageActions;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isMine = message.senderId == myId;
        return Column(
          children: [
            if (shouldShowTimestamp(index))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      formatTimestamp(message.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            MessageBubble(
              message: message,
              isMine: isMine,
              myName: myName,
              peerName: peerName,
              myAvatarUrl: myAvatarUrl,
              peerAvatarUrl: peerAvatarUrl,
              onPlayVideo: onPlayVideo,
              onPreviewImage: onPreviewImage,
              onOpenDynamicPhoto: onOpenDynamicPhoto,
              urlResolver: urlResolver,
              localCoverBytes: localCoverBytesByMessageId[message.id],
              localCoverPath: localCoverPathByMessageId[message.id],
              onRetry: isMine && message.isFailed
                  ? () => onRetryMessage(message)
                  : null,
              onOpenFile: () => onOpenFileMessage(message),
              onLongPress: () => onShowMessageActions(message),
            ),
          ],
        );
      },
    );
  }
}
