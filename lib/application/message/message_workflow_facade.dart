import 'package:vox_flutter/models/attachment_upload_response.dart';
import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/services/attachment/attachment_service.dart';

class MessageWorkflowFacade {
  MessageWorkflowFacade({
    required this.messageEvents,
    required this.attachmentService,
    required this.prefetchPeer,
    required this.clearUnread,
    required this.refreshSessions,
    required this.loadHistory,
    required this.markRead,
    required this.sendText,
    required this.sendImage,
    required this.sendVideo,
    required this.sendDynamicPhoto,
    required this.uploadFileFromPath,
    required this.clearConversation,
  });

  final Stream<ChatMessage> messageEvents;
  final AttachmentService attachmentService;
  final Future<void> Function(int peerId) prefetchPeer;
  final void Function(int peerId) clearUnread;
  final Future<void> Function() refreshSessions;
  final Future<List<ChatMessage>> Function({
    required int userId,
    required int peerId,
    required int page,
    required int size,
  }) loadHistory;
  final Future<void> Function(int messageId) markRead;
  final Future<int> Function({
    required int senderId,
    required int receiverId,
    required String content,
  }) sendText;
  final Future<int> Function({
    required int senderId,
    required int receiverId,
    required int resourceId,
  }) sendImage;
  final Future<int> Function({
    required int senderId,
    required int receiverId,
    required int videoResourceId,
    int? coverResourceId,
  }) sendVideo;
  final Future<int> Function({
    required int senderId,
    required int receiverId,
    required int coverId,
    required int videoId,
  }) sendDynamicPhoto;
  final Future<AttachmentUploadResponse> Function({
    required String filePath,
    int? userId,
  }) uploadFileFromPath;
  final Future<void> Function({
    required int userId,
    required int peerId,
  }) clearConversation;
}
