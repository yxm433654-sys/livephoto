import 'dart:typed_data';

import 'package:vox_flutter/application/message/message_workflow_facade.dart';
import 'package:vox_flutter/models/chat_media.dart';
import 'package:vox_flutter/models/attachment_upload_response.dart';
import 'package:vox_flutter/models/media_draft_metadata.dart';
import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/ui/chat/local_message_factory.dart';
import 'package:vox_flutter/utils/user_error_message.dart';

class MessageSender {
  MessageSender({
    required this.workflow,
    required this.peerId,
    required this.senderId,
    this.localMessageFactory,
    required this.nextTempId,
    required this.insertLocalMessage,
    required this.replaceMessage,
    required this.removeLocalMessage,
    required this.setSending,
    required this.showError,
  });

  final MessageWorkflowFacade workflow;
  final int peerId;
  final int senderId;
  final LocalMessageFactory? localMessageFactory;
  final int Function() nextTempId;
  final void Function(
    ChatMessage message, {
    Uint8List? localCoverBytes,
    String? localCoverPath,
  }) insertLocalMessage;
  final void Function(int tempId, ChatMessage message) replaceMessage;
  final void Function(int tempId) removeLocalMessage;
  final void Function(bool sending) setSending;
  final void Function(String message) showError;

  Future<void> sendText({
    required String text,
    required void Function() onQueued,
    required void Function(String text) onFailedRestore,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final tempId = nextTempId();
    insertLocalMessage(
      _buildLocalMessage(
        id: tempId,
        type: 'TEXT',
        content: trimmed,
        status: 'SENDING',
      ),
    );
    onQueued();

    await _runSend(
      tempId: tempId,
      sendRemote: () => workflow.sendText(
        senderId: senderId,
        receiverId: peerId,
        content: trimmed,
      ),
      buildResolvedMessage: (messageId) => _buildLocalMessage(
        id: messageId,
        type: 'TEXT',
        content: trimmed,
        status: 'SENT',
      ),
      onError: () {
        onFailedRestore(trimmed);
      },
    );
  }

  Future<void> sendImageFromPath({
    required String filePath,
    Uint8List? previewBytes,
    MediaDraftMetadata? metadata,
  }) async {
    final tempId = nextTempId();
    insertLocalMessage(
      _buildLocalMessage(
        id: tempId,
        type: 'IMAGE',
        media: _buildPlaceholderMedia(
          mediaKind: 'IMAGE',
          metadata: metadata,
          fallbackAspectRatio: 1.0,
        ),
        status: 'SENDING',
      ),
      localCoverBytes: previewBytes,
      localCoverPath: filePath,
    );

    await _runSend(
      tempId: tempId,
      sendRemote: () async {
        final upload = await workflow.uploadFileFromPath(
          filePath: filePath,
          userId: senderId,
        );
        final messageId = await workflow.sendImage(
          senderId: senderId,
          receiverId: peerId,
          resourceId: upload.fileId!,
        );
        return _ResolvedSend(
          message: _buildLocalMessage(
            id: messageId,
            type: 'IMAGE',
            resourceId: upload.fileId,
            coverUrl: upload.url,
            videoUrl: upload.url,
            media: _buildImageMedia(upload, metadata),
            status: 'SENT',
          ),
        );
      },
    );
  }

  Future<void> sendVideoFromPath({
    required String filePath,
    Uint8List? previewBytes,
    MediaDraftMetadata? metadata,
  }) async {
    final tempId = nextTempId();
    insertLocalMessage(
      _buildLocalMessage(
        id: tempId,
        type: 'VIDEO',
        media: _buildPlaceholderMedia(
          mediaKind: 'VIDEO',
          metadata: metadata,
          fallbackAspectRatio: 9 / 16,
        ),
        status: 'SENDING',
      ),
      localCoverBytes: previewBytes,
    );

    await _runSend(
      tempId: tempId,
      sendRemote: () async {
        final upload = await workflow.uploadFileFromPath(
          filePath: filePath,
          userId: senderId,
        );
        final playId = upload.videoId ?? upload.fileId;
        if (playId == null) {
          throw Exception('视频上传后未返回资源 ID');
        }
        final messageId = await workflow.sendVideo(
          senderId: senderId,
          receiverId: peerId,
          videoResourceId: playId,
          coverResourceId: upload.coverId,
        );
        return _ResolvedSend(
          message: _buildLocalMessage(
            id: messageId,
            type: 'VIDEO',
            resourceId: upload.coverId,
            videoResourceId: playId,
            coverUrl: upload.coverUrl,
            videoUrl: upload.videoUrl ?? upload.url,
            media: _buildVideoMedia(upload, metadata),
            status: 'SENT',
          ),
        );
      },
    );
  }

  Future<void> sendDynamicPhoto({
    required String coverPath,
    Uint8List? previewBytes,
    required Future<AttachmentUploadResponse> Function(int userId) upload,
    MediaDraftMetadata? metadata,
  }) async {
    final tempId = nextTempId();
    insertLocalMessage(
      _buildLocalMessage(
        id: tempId,
        type: 'DYNAMIC_PHOTO',
        media: _buildPlaceholderMedia(
          mediaKind: 'DYNAMIC_PHOTO',
          metadata: metadata,
          fallbackAspectRatio: 3 / 4,
        ),
        status: 'SENDING',
      ),
      localCoverBytes: previewBytes,
      localCoverPath: coverPath,
    );

    await _runSend(
      tempId: tempId,
      sendRemote: () async {
        final uploaded = await upload(senderId);
        if (uploaded.coverId == null || uploaded.videoId == null) {
          throw Exception('动态照片上传后未返回完整资源');
        }
        final messageId = await workflow.sendDynamicPhoto(
          senderId: senderId,
          receiverId: peerId,
          coverId: uploaded.coverId!,
          videoId: uploaded.videoId!,
        );
        return _ResolvedSend(
          message: _buildLocalMessage(
            id: messageId,
            type: 'DYNAMIC_PHOTO',
            resourceId: uploaded.coverId,
            videoResourceId: uploaded.videoId,
            coverUrl: uploaded.coverUrl,
            videoUrl: uploaded.videoUrl,
            media: _buildDynamicMedia(uploaded, metadata),
            status: 'SENT',
          ),
        );
      },
    );
  }

  Future<void> _runSend({
    required int tempId,
    required Future<Object> Function() sendRemote,
    ChatMessage Function(int messageId)? buildResolvedMessage,
    void Function()? onError,
  }) async {
    setSending(true);
    try {
      final result = await sendRemote();
      if (result is _ResolvedSend) {
        replaceMessage(tempId, result.message);
      } else if (result is int && buildResolvedMessage != null) {
        replaceMessage(tempId, buildResolvedMessage(result));
      } else {
        throw Exception('Unsupported send result');
      }
    } catch (e) {
      removeLocalMessage(tempId);
      onError?.call();
      showError(UserErrorMessage.from(e));
    } finally {
      setSending(false);
    }
  }

  ChatMessage _buildLocalMessage({
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
    final factory = localMessageFactory ??
        LocalMessageFactory(senderId: senderId, receiverId: peerId);
    return factory.build(
      id: id,
      type: type,
      content: content,
      resourceId: resourceId,
      videoResourceId: videoResourceId,
      coverUrl: coverUrl,
      videoUrl: videoUrl,
      media: media,
      status: status,
    );
  }

  ChatMedia _buildPlaceholderMedia({
    required String mediaKind,
    MediaDraftMetadata? metadata,
    required double fallbackAspectRatio,
  }) {
    return ChatMedia(
      mediaKind: mediaKind,
      processingStatus: 'PROCESSING',
      resourceId: null,
      coverResourceId: null,
      playResourceId: null,
      coverUrl: null,
      playUrl: null,
      width: metadata?.width,
      height: metadata?.height,
      duration: metadata?.durationSeconds,
      aspectRatio:
          metadata?.aspectRatio(fallbackAspectRatio) ?? fallbackAspectRatio,
      sourceType: null,
    );
  }

  ChatMedia _buildImageMedia(
    AttachmentUploadResponse upload,
    MediaDraftMetadata? metadata,
  ) {
    final width = upload.width ?? metadata?.width;
    final height = upload.height ?? metadata?.height;
    return ChatMedia(
      mediaKind: 'IMAGE',
      processingStatus: 'READY',
      resourceId: upload.fileId,
      coverResourceId: upload.fileId,
      playResourceId: upload.fileId,
      coverUrl: upload.url,
      playUrl: upload.url,
      width: width,
      height: height,
      duration: upload.duration ?? metadata?.durationSeconds,
      aspectRatio:
          _aspectRatio(width, height, metadata?.aspectRatio(1.0) ?? 1.0),
      sourceType: upload.sourceType,
    );
  }

  ChatMedia _buildVideoMedia(
    AttachmentUploadResponse upload,
    MediaDraftMetadata? metadata,
  ) {
    final coverId = upload.coverId;
    final playId = upload.videoId ?? upload.fileId;
    final width = upload.width ?? metadata?.width;
    final height = upload.height ?? metadata?.height;
    return ChatMedia(
      mediaKind: 'VIDEO',
      processingStatus: 'PROCESSING',
      resourceId: playId,
      coverResourceId: coverId,
      playResourceId: playId,
      coverUrl: upload.coverUrl,
      playUrl: upload.videoUrl ?? upload.url,
      width: width,
      height: height,
      duration: upload.duration ?? metadata?.durationSeconds,
      aspectRatio:
          _aspectRatio(width, height, metadata?.aspectRatio(9 / 16) ?? 9 / 16),
      sourceType: upload.sourceType,
    );
  }

  ChatMedia _buildDynamicMedia(
    AttachmentUploadResponse upload,
    MediaDraftMetadata? metadata,
  ) {
    final width = upload.width ?? metadata?.width;
    final height = upload.height ?? metadata?.height;
    return ChatMedia(
      mediaKind: 'DYNAMIC_PHOTO',
      processingStatus: 'PROCESSING',
      resourceId: upload.videoId,
      coverResourceId: upload.coverId,
      playResourceId: upload.videoId,
      coverUrl: upload.coverUrl,
      playUrl: upload.videoUrl,
      width: width,
      height: height,
      duration: upload.duration ?? metadata?.durationSeconds,
      aspectRatio:
          _aspectRatio(width, height, metadata?.aspectRatio(3 / 4) ?? 3 / 4),
      sourceType: upload.sourceType,
    );
  }

  double _aspectRatio(int? width, int? height, double fallback) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return fallback;
    }
    return width / height;
  }
}

class _ResolvedSend {
  const _ResolvedSend({required this.message});

  final ChatMessage message;
}


