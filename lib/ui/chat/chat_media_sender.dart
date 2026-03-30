import 'dart:typed_data';

import 'package:dynamic_photo_chat_flutter/models/chat_media.dart';
import 'package:dynamic_photo_chat_flutter/models/file_upload_response.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/ui/chat/chat_local_message_factory.dart';

class ChatMediaSender {
  ChatMediaSender({
    required this.appState,
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

  final AppState appState;
  final int peerId;
  final int senderId;
  final ChatLocalMessageFactory? localMessageFactory;
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

  Future<void> sendImageFromPath({
    required String filePath,
    Uint8List? previewBytes,
  }) async {
    final tempId = nextTempId();
    insertLocalMessage(
      _buildLocalMessage(
        id: tempId,
        type: 'IMAGE',
        media: _buildPlaceholderMedia(
          mediaKind: 'IMAGE',
          aspectRatio: 1.0,
        ),
        status: 'SENDING',
      ),
      localCoverBytes: previewBytes,
      localCoverPath: filePath,
    );

    setSending(true);
    try {
      final upload = await appState.files.uploadNormalFromPath(
        filePath: filePath,
        userId: senderId,
      );
      final messageId = await appState.messages.sendImage(
        senderId: senderId,
        receiverId: peerId,
        resourceId: upload.fileId!,
      );
      replaceMessage(
        tempId,
        _buildLocalMessage(
          id: messageId,
          type: 'IMAGE',
          resourceId: upload.fileId,
          coverUrl: upload.url,
          videoUrl: upload.url,
          media: _buildImageMedia(upload),
          status: 'SENT',
        ),
      );
    } catch (e) {
      removeLocalMessage(tempId);
      showError(_toUserError(e));
    } finally {
      setSending(false);
    }
  }

  Future<void> sendVideoFromPath({
    required String filePath,
    Uint8List? previewBytes,
  }) async {
    final tempId = nextTempId();
    insertLocalMessage(
      _buildLocalMessage(
        id: tempId,
        type: 'VIDEO',
        media: _buildPlaceholderMedia(
          mediaKind: 'VIDEO',
          aspectRatio: 9 / 16,
        ),
        status: 'SENDING',
      ),
      localCoverBytes: previewBytes,
    );

    setSending(true);
    try {
      final upload = await appState.files.uploadNormalFromPath(
        filePath: filePath,
        userId: senderId,
      );
      final playId = upload.videoId ?? upload.fileId;
      if (playId == null) {
        throw Exception('Video upload did not return a resource id.');
      }
      final messageId = await appState.messages.sendVideo(
        senderId: senderId,
        receiverId: peerId,
        videoResourceId: playId,
        coverResourceId: upload.coverId,
      );
      replaceMessage(
        tempId,
        _buildLocalMessage(
          id: messageId,
          type: 'VIDEO',
          resourceId: upload.coverId,
          videoResourceId: playId,
          coverUrl: upload.coverUrl,
          videoUrl: upload.videoUrl ?? upload.url,
          media: _buildVideoMedia(upload),
          status: 'SENT',
        ),
      );
    } catch (e) {
      removeLocalMessage(tempId);
      showError(_toUserError(e));
    } finally {
      setSending(false);
    }
  }

  Future<void> sendDynamicPhoto({
    required String coverPath,
    Uint8List? previewBytes,
    required Future<FileUploadResponse> Function(int userId) upload,
  }) async {
    final tempId = nextTempId();
    insertLocalMessage(
      _buildLocalMessage(
        id: tempId,
        type: 'DYNAMIC_PHOTO',
        media: _buildPlaceholderMedia(
          mediaKind: 'DYNAMIC_PHOTO',
          aspectRatio: 3 / 4,
        ),
        status: 'SENDING',
      ),
      localCoverBytes: previewBytes,
      localCoverPath: coverPath,
    );

    setSending(true);
    try {
      final uploaded = await upload(senderId);
      if (uploaded.coverId == null || uploaded.videoId == null) {
        throw Exception('Dynamic photo upload did not return full resources.');
      }
      final messageId = await appState.messages.sendDynamicPhoto(
        senderId: senderId,
        receiverId: peerId,
        coverId: uploaded.coverId!,
        videoId: uploaded.videoId!,
      );
      replaceMessage(
        tempId,
        _buildLocalMessage(
          id: messageId,
          type: 'DYNAMIC_PHOTO',
          resourceId: uploaded.coverId,
          videoResourceId: uploaded.videoId,
          coverUrl: uploaded.coverUrl,
          videoUrl: uploaded.videoUrl,
          media: _buildDynamicMedia(uploaded),
          status: 'SENT',
        ),
      );
    } catch (e) {
      removeLocalMessage(tempId);
      showError(_toUserError(e));
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
        ChatLocalMessageFactory(senderId: senderId, receiverId: peerId);
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
    required double aspectRatio,
  }) {
    return ChatMedia(
      mediaKind: mediaKind,
      processingStatus: 'PROCESSING',
      resourceId: null,
      coverResourceId: null,
      playResourceId: null,
      coverUrl: null,
      playUrl: null,
      width: null,
      height: null,
      duration: null,
      aspectRatio: aspectRatio,
      sourceType: null,
    );
  }

  ChatMedia _buildImageMedia(FileUploadResponse upload) {
    return ChatMedia(
      mediaKind: 'IMAGE',
      processingStatus: 'READY',
      resourceId: upload.fileId,
      coverResourceId: upload.fileId,
      playResourceId: upload.fileId,
      coverUrl: upload.url,
      playUrl: upload.url,
      width: upload.width,
      height: upload.height,
      duration: upload.duration,
      aspectRatio: _aspectRatio(upload.width, upload.height, 1.0),
      sourceType: upload.sourceType,
    );
  }

  ChatMedia _buildVideoMedia(FileUploadResponse upload) {
    final coverId = upload.coverId;
    final playId = upload.videoId ?? upload.fileId;
    return ChatMedia(
      mediaKind: 'VIDEO',
      processingStatus: 'PROCESSING',
      resourceId: playId,
      coverResourceId: coverId,
      playResourceId: playId,
      coverUrl: upload.coverUrl,
      playUrl: upload.videoUrl ?? upload.url,
      width: upload.width,
      height: upload.height,
      duration: upload.duration,
      aspectRatio: _aspectRatio(upload.width, upload.height, 9 / 16),
      sourceType: upload.sourceType,
    );
  }

  ChatMedia _buildDynamicMedia(FileUploadResponse upload) {
    return ChatMedia(
      mediaKind: 'DYNAMIC_PHOTO',
      processingStatus: 'PROCESSING',
      resourceId: upload.coverId,
      coverResourceId: upload.coverId,
      playResourceId: upload.videoId,
      coverUrl: upload.coverUrl,
      playUrl: upload.videoUrl,
      width: upload.width,
      height: upload.height,
      duration: upload.duration,
      aspectRatio: _aspectRatio(upload.width, upload.height, 3 / 4),
      sourceType: upload.sourceType,
    );
  }

  double _aspectRatio(int? width, int? height, double fallback) {
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return fallback;
  }

  String _toUserError(Object error) {
    final text = error.toString().trim();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }
}
