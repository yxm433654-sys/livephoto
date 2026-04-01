import 'package:vox_flutter/models/chat_media.dart';
import 'package:vox_flutter/models/message.dart';

class LocalMessageFactory {
  const LocalMessageFactory({
    required this.senderId,
    required this.receiverId,
  });

  final int senderId;
  final int receiverId;

  ChatMessage build({
    required int id,
    required String type,
    String? content,
    int? resourceId,
    int? videoResourceId,
    String? coverUrl,
    String? videoUrl,
    ChatMedia? media,
    String? status,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      type: type,
      content: content,
      resourceId: resourceId,
      videoResourceId: videoResourceId,
      coverUrl: coverUrl,
      videoUrl: videoUrl,
      media: media,
      status: status,
      createdAt: DateTime.now(),
    );
  }
}
