import 'dart:async';
import 'dart:io';

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
    required this.onConversationCleared,
    required this.showSnack,
  });

  final BuildContext context;
  final MessageWorkflowFacade workflow;
  final int peerId;
  final int currentUserId;
  final DynamicPhotoAdapter dynamicPhotoAdapter;
  final MessageSender messageSender;
  final VoidCallback onConversationCleared;
  final void Function(String message) showSnack;

  Future<void> showAttachMenu() async {
    final action = await ChatMediaPicker.showAttachMenu(context);
    if (action != null) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
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
    final assets = await ChatMediaPicker.pickAssets(
      context: context,
      mode: ChatAssetPickerMode.image,
      showSnack: showSnack,
    );
    if (assets.isEmpty) return;
    unawaited(_sendSelectedImages(assets));
  }

  Future<void> pickGalleryVideo() async {
    final assets = await ChatMediaPicker.pickAssets(
      context: context,
      mode: ChatAssetPickerMode.video,
      showSnack: showSnack,
    );
    if (assets.isEmpty) return;
    unawaited(_sendSelectedVideos(assets));
  }

  Future<void> pickGalleryDynamicPhoto() async {
    final asset = await ChatMediaPicker.pickAsset(
      context: context,
      mode: ChatAssetPickerMode.livePhoto,
      showSnack: showSnack,
    );
    if (asset == null) return;

    final previewBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(320, 320),
    );
    await Future<void>.delayed(const Duration(milliseconds: 16));

    final picked = await dynamicPhotoAdapter.detect(asset);
    if (picked == null) {
      showSnack('无法读取所选动态照片。');
      return;
    }

    final coverFile = File(picked.coverPath);
    if (!await coverFile.exists()) {
      showSnack('无法读取动态照片封面。');
      return;
    }

    final coverLength = await coverFile.length();
    if (coverLength > ChatMediaPicker.imageMaxBytes) {
      showSnack('动态照片封面大小 ${_formatBytes(coverLength)}，超过 20MB。');
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

  Future<void> _sendSelectedImages(List<AssetEntity> assets) async {
    for (final asset in assets) {
      final file = await _resolveFile(asset);
      if (file == null) {
        showSnack('无法读取所选图片。');
        continue;
      }

      final length = await file.length();
      if (length > ChatMediaPicker.imageMaxBytes) {
        showSnack('图片大小 ${_formatBytes(length)}，超过 20MB，已跳过。');
        continue;
      }

      final previewBytes = await asset.thumbnailDataWithSize(
        const ThumbnailSize(320, 320),
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
  }

  Future<void> _sendSelectedVideos(List<AssetEntity> assets) async {
    for (final asset in assets) {
      final file = await _resolveFile(asset);
      if (file == null) {
        showSnack('无法读取所选视频。');
        continue;
      }

      final length = await file.length();
      if (length > ChatMediaPicker.videoMaxBytes) {
        showSnack('视频大小 ${_formatBytes(length)}，超过 256MB，已跳过。');
        continue;
      }

      final previewBytes = await asset.thumbnailDataWithSize(
        const ThumbnailSize(320, 320),
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
  }

  String _formatBytes(int bytes) {
    const units = <String>['B', 'KB', 'MB', 'GB'];
    double value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final digits = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
  }

  Future<File?> _resolveFile(AssetEntity asset) async {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    return asset.file;
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

