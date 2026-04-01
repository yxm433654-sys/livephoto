import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:vox_flutter/application/message/message_workflow_facade.dart';
import 'package:vox_flutter/models/media_draft_metadata.dart';
import 'package:vox_flutter/services/attachment/dynamic_photo_upload_service.dart';
import 'package:vox_flutter/ui/chat/chat_media_picker.dart';
import 'package:vox_flutter/ui/chat/dynamic_photo_adapter.dart';
import 'package:vox_flutter/ui/chat/message_sender.dart';
import 'package:vox_flutter/utils/media_downloader.dart';
import 'package:vox_flutter/utils/user_error_message.dart';

class ChatMediaActionHandler {
  const ChatMediaActionHandler({
    required this.context,
    required this.workflow,
    required this.peerId,
    required this.currentUserId,
    required this.dynamicPhotoAdapter,
    required this.messageSender,
    required this.sending,
    required this.onConversationCleared,
    required this.showSnack,
  });

  final BuildContext context;
  final MessageWorkflowFacade workflow;
  final int peerId;
  final int currentUserId;
  final DynamicPhotoAdapter dynamicPhotoAdapter;
  final MessageSender messageSender;
  final bool sending;
  final VoidCallback onConversationCleared;
  final void Function(String message) showSnack;

  Future<void> showAttachMenu() async {
    final action = await ChatMediaPicker.showAttachMenu(context);
    switch (action) {
      case ChatAttachAction.galleryImage:
        await pickGalleryImage();
        break;
      case ChatAttachAction.galleryVideo:
        await pickGalleryVideo();
        break;
      case ChatAttachAction.livePhoto:
        await pickGalleryDynamicPhoto();
        break;
      case null:
        break;
    }
  }

  Future<void> pickGalleryImage() async {
    if (sending) return;
    final asset = await ChatMediaPicker.pickAsset(
      context: context,
      mode: ChatAssetPickerMode.image,
      showSnack: showSnack,
    );
    if (asset == null) return;

    final file = await asset.originFile ?? await asset.file;
    if (file == null) {
      showSnack('无法读取所选图片。');
      return;
    }

    final previewBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(512, 512),
    );

    await messageSender.sendImageFromPath(
      filePath: file.path,
      previewBytes: previewBytes,
      metadata: MediaDraftMetadata(
        width: asset.width,
        height: asset.height,
      ),
    );
  }

  Future<void> pickGalleryVideo() async {
    if (sending) return;
    final asset = await ChatMediaPicker.pickAsset(
      context: context,
      mode: ChatAssetPickerMode.video,
      showSnack: showSnack,
    );
    if (asset == null) return;

    final file = await asset.originFile ?? await asset.file;
    if (file == null) {
      showSnack('无法读取所选视频。');
      return;
    }

    final previewBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(512, 512),
    );

    await messageSender.sendVideoFromPath(
      filePath: file.path,
      previewBytes: previewBytes,
      metadata: MediaDraftMetadata(
        width: asset.width,
        height: asset.height,
        durationSeconds: asset.duration.toDouble(),
      ),
    );
  }

  Future<void> pickGalleryDynamicPhoto() async {
    if (sending) return;
    final asset = await ChatMediaPicker.pickAsset(
      context: context,
      mode: ChatAssetPickerMode.livePhoto,
      showSnack: showSnack,
    );
    if (asset == null) return;

    final previewBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(512, 512),
    );
    final picked = await dynamicPhotoAdapter.detect(asset);
    if (picked == null) {
      showSnack('无法读取所选动态照片。');
      return;
    }

    final uploader = DynamicPhotoUploadService(workflow.attachmentService);
    await messageSender.sendDynamicPhoto(
      coverPath: picked.coverPath,
      previewBytes: previewBytes,
      upload: (userId) => uploader.upload(pickResult: picked, userId: userId),
      metadata: MediaDraftMetadata(
        width: asset.width,
        height: asset.height,
        durationSeconds: asset.duration.toDouble(),
      ),
    );
  }

  Future<void> clearConversation() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('清空聊天记录'),
            content: const Text('这会清空当前会话在服务器上的聊天记录。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('清空'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      await workflow.clearConversation(
        userId: currentUserId,
        peerId: peerId,
      );
      onConversationCleared();
      showSnack('聊天记录已清空。');
    } catch (error) {
      showSnack(UserErrorMessage.from(error));
    }
  }

  Future<void> clearMediaCache() async {
    try {
      await MediaDownloader.clearCache();
      await DefaultCacheManager().emptyCache();
      imageCache.clear();
      imageCache.clearLiveImages();
      showSnack('媒体缓存已清空。');
    } catch (error) {
      showSnack(UserErrorMessage.from(error));
    }
  }
}
