import 'dart:io';
import 'dart:typed_data';

import 'package:vox_flutter/application/message/message_workflow_facade.dart';
import 'package:vox_flutter/models/attachment_upload_response.dart';
import 'package:vox_flutter/models/chat_media.dart';
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
    required this.getMessageById,
    required this.getLocalPathByMessageId,
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
  final ChatMessage? Function(int messageId) getMessageById;
  final String? Function(int messageId) getLocalPathByMessageId;
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
      buildResolvedMessage: (_, messageId) => _buildLocalMessage(
        id: messageId,
        type: 'TEXT',
        content: trimmed,
        status: 'SENT',
      ),
      onError: () => onFailedRestore(trimmed),
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
      sendRemote: () => _uploadAndSendImage(filePath, metadata),
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
      localCoverPath: filePath,
    );

    await _runSend(
      tempId: tempId,
      sendRemote: () => _uploadAndSendVideo(filePath, metadata),
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

  Future<void> sendFileFromPath({
    required String filePath,
    String? fileName,
    int? fileSize,
  }) async {
    final tempId = nextTempId();
    final resolvedName = _resolveFileName(filePath, fileName);
    insertLocalMessage(
      _buildLocalMessage(
        id: tempId,
        type: 'FILE',
        content: resolvedName,
        media: _buildFileMedia(filePath: filePath, size: fileSize),
        status: 'SENDING',
      ),
      localCoverPath: filePath,
    );

    await _runSend(
      tempId: tempId,
      sendRemote: () => _uploadAndSendFile(filePath, resolvedName),
    );
  }

  Future<void> retryMessage(ChatMessage message) async {
    if (!message.isFailed) {
      return;
    }

    replaceMessage(message.id, message.copyWith(status: 'SENDING'));
    await _runSend(
      tempId: message.id,
      sendRemote: () => _retryRemote(message),
      onError: () {
        final latest = getMessageById(message.id);
        if (latest != null && latest.type.toUpperCase() == 'TEXT') {
          showError('发送失败，可以点击消息重试，或复制后重新发送。');
        }
      },
    );
  }

  Future<Object> _retryRemote(ChatMessage message) async {
    final type = message.type.toUpperCase();
    switch (type) {
      case 'TEXT':
        return workflow.sendText(
          senderId: senderId,
          receiverId: peerId,
          content: message.content ?? '',
        );
      case 'IMAGE':
        final resourceId = message.resourceId ?? message.media?.resourceId;
        if (resourceId != null) {
          return workflow.sendImage(
            senderId: senderId,
            receiverId: peerId,
            resourceId: resourceId,
          );
        }
        final imagePath = getLocalPathByMessageId(message.id);
        if (imagePath != null && imagePath.trim().isNotEmpty) {
          return _uploadAndSendImage(imagePath, null);
        }
        throw Exception('无法重试这条图片消息，请重新选择图片。');
      case 'VIDEO':
        final playId = message.videoResourceId ?? message.media?.playResourceId;
        if (playId != null) {
          return workflow.sendVideo(
            senderId: senderId,
            receiverId: peerId,
            videoResourceId: playId,
            coverResourceId:
                message.resourceId ?? message.media?.coverResourceId,
          );
        }
        final videoPath = getLocalPathByMessageId(message.id);
        if (videoPath != null && videoPath.trim().isNotEmpty) {
          return _uploadAndSendVideo(videoPath, null);
        }
        throw Exception('无法重试这条视频消息，请重新选择视频。');
      case 'DYNAMIC_PHOTO':
        final coverId = message.resourceId ?? message.media?.coverResourceId;
        final videoId = message.videoResourceId ?? message.media?.playResourceId;
        if (coverId == null || videoId == null) {
          throw Exception('无法重试这条动态照片，请重新选择动态照片。');
        }
        return workflow.sendDynamicPhoto(
          senderId: senderId,
          receiverId: peerId,
          coverId: coverId,
          videoId: videoId,
        );
      case 'FILE':
        final fileResourceId = message.resourceId ?? message.media?.resourceId;
        if (fileResourceId != null) {
          return workflow.sendFile(
            senderId: senderId,
            receiverId: peerId,
            resourceId: fileResourceId,
            fileName: message.content ?? '文件',
          );
        }
        final filePath = getLocalPathByMessageId(message.id);
        if (filePath != null && filePath.trim().isNotEmpty) {
          return _uploadAndSendFile(
            filePath,
            _resolveFileName(filePath, message.content),
          );
        }
        throw Exception('无法重试这条文件消息，请重新选择文件。');
      default:
        throw Exception('暂不支持重试这种消息。');
    }
  }

  Future<void> _runSend({
    required int tempId,
    required Future<Object> Function() sendRemote,
    ChatMessage Function(ChatMessage currentMessage, int messageId)?
        buildResolvedMessage,
    void Function()? onError,
  }) async {
    setSending(true);
    try {
      final result = await sendRemote();
      final currentMessage = getMessageById(tempId);
      if (currentMessage == null) {
        return;
      }

      if (result is _ResolvedSend) {
        replaceMessage(tempId, result.message);
      } else if (result is int) {
        final resolvedMessage = buildResolvedMessage == null
            ? currentMessage.copyWith(id: result, status: 'SENT')
            : buildResolvedMessage(currentMessage, result);
        replaceMessage(tempId, resolvedMessage);
      } else {
        throw Exception('Unsupported send result');
      }
    } catch (e) {
      final failed = getMessageById(tempId);
      if (failed != null) {
        replaceMessage(tempId, failed.copyWith(status: 'FAILED'));
      } else {
        removeLocalMessage(tempId);
      }
      onError?.call();
      showError(UserErrorMessage.from(e));
    } finally {
      setSending(false);
    }
  }

  Future<_ResolvedSend> _uploadAndSendImage(
    String filePath,
    MediaDraftMetadata? metadata,
  ) async {
    final upload = await workflow.uploadFileFromPath(
      filePath: filePath,
      userId: senderId,
    );
    if ((upload.fileType ?? '').toUpperCase() == 'DYNAMIC_PHOTO') {
      final coverId = upload.coverId;
      final videoId = upload.videoId;
      if (coverId == null || videoId == null) {
        throw Exception('动态照片上传后未返回完整资源');
      }
      final messageId = await workflow.sendDynamicPhoto(
        senderId: senderId,
        receiverId: peerId,
        coverId: coverId,
        videoId: videoId,
      );
      return _ResolvedSend(
        message: _buildLocalMessage(
          id: messageId,
          type: 'DYNAMIC_PHOTO',
          resourceId: coverId,
          videoResourceId: videoId,
          coverUrl: upload.coverUrl,
          videoUrl: upload.videoUrl,
          media: _buildDynamicMedia(upload, metadata),
          status: 'SENT',
        ),
      );
    }
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
  }

  Future<_ResolvedSend> _uploadAndSendVideo(
    String filePath,
    MediaDraftMetadata? metadata,
  ) async {
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
  }

  Future<_ResolvedSend> _uploadAndSendFile(
    String filePath,
    String fileName,
  ) async {
    final upload = await workflow.uploadFileFromPath(
      filePath: filePath,
      userId: senderId,
    );
    final resourceId = upload.fileId;
    if (resourceId == null) {
      throw Exception('文件上传后未返回资源 ID');
    }
    final messageId = await workflow.sendFile(
      senderId: senderId,
      receiverId: peerId,
      resourceId: resourceId,
      fileName: fileName,
    );
    return _ResolvedSend(
      message: _buildLocalMessage(
        id: messageId,
        type: 'FILE',
        content: fileName,
        resourceId: resourceId,
        media: _buildUploadedFileMedia(upload),
        status: 'SENT',
      ),
    );
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

  ChatMedia _buildFileMedia({
    required String filePath,
    int? size,
  }) {
    return ChatMedia(
      mediaKind: 'FILE',
      processingStatus: 'PROCESSING',
      resourceId: null,
      coverResourceId: null,
      playResourceId: null,
      coverUrl: null,
      playUrl: null,
      width: null,
      height: null,
      duration: size?.toDouble(),
      aspectRatio: null,
      sourceType: _resolveFileExtension(filePath),
    );
  }

  ChatMedia _buildUploadedFileMedia(AttachmentUploadResponse upload) {
    return ChatMedia(
      mediaKind: 'FILE',
      processingStatus: 'READY',
      resourceId: upload.fileId,
      coverResourceId: upload.fileId,
      playResourceId: upload.fileId,
      coverUrl: upload.url,
      playUrl: upload.url,
      width: null,
      height: null,
      duration: upload.size?.toDouble(),
      aspectRatio: null,
      sourceType: upload.mimeType ?? upload.fileType,
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

  String _resolveFileName(String filePath, String? fallback) {
    if (fallback != null && fallback.trim().isNotEmpty) {
      return fallback.trim();
    }
    return filePath.split(Platform.pathSeparator).last;
  }

  String? _resolveFileExtension(String filePath) {
    final fileName = _resolveFileName(filePath, null);
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot >= fileName.length - 1) {
      return null;
    }
    return fileName.substring(dot + 1).toLowerCase();
  }
}

class _ResolvedSend {
  const _ResolvedSend({required this.message});

  final ChatMessage message;
}
