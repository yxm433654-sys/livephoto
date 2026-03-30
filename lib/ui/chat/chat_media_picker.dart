import 'dart:io';
import 'dart:typed_data';

import 'package:dynamic_photo_chat_flutter/utils/live_photo_detector.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

enum ChatAttachAction {
  galleryImage,
  galleryVideo,
  livePhoto,
}

enum ChatAssetPickerMode {
  image,
  video,
  livePhoto,
}

class ChatMediaPicker {
  const ChatMediaPicker._();

  static Future<ChatAttachAction?> showAttachMenu(BuildContext context) {
    return showModalBottomSheet<ChatAttachAction>(
      context: context,
      backgroundColor: const Color(0xFFF7F8FA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '发送媒体',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _AttachTile(
                      icon: Icons.image_outlined,
                      label: '图片',
                      color: const Color(0xFFE0F2FE),
                      iconColor: const Color(0xFF0284C7),
                      onTap: () => Navigator.of(sheetContext).pop(ChatAttachAction.galleryImage),
                    ),
                    _AttachTile(
                      icon: Icons.smart_display_outlined,
                      label: '视频',
                      color: const Color(0xFFDCFCE7),
                      iconColor: const Color(0xFF16A34A),
                      onTap: () => Navigator.of(sheetContext).pop(ChatAttachAction.galleryVideo),
                    ),
                    _AttachTile(
                      icon: Icons.motion_photos_on_outlined,
                      label: 'Live Photo',
                      color: const Color(0xFFFCE7F3),
                      iconColor: const Color(0xFFDB2777),
                      onTap: () => Navigator.of(sheetContext).pop(ChatAttachAction.livePhoto),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<AssetEntity?> pickAsset({
    required BuildContext context,
    required ChatAssetPickerMode mode,
    required void Function(String message) showSnack,
  }) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      showSnack('请先允许访问媒体库');
      return null;
    }

    final paths = await PhotoManager.getAssetPathList(
      type: mode == ChatAssetPickerMode.video ? RequestType.video : RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(sizeConstraint: SizeConstraint()),
        videoOption: const FilterOption(sizeConstraint: SizeConstraint()),
      ),
    );
    if (paths.isEmpty) {
      showSnack('没有找到媒体内容');
      return null;
    }

    final rawAssets = await paths.first.getAssetListPaged(page: 0, size: 96);
    final assets = await _filterAssetsForMode(rawAssets, mode);
    if (assets.isEmpty) {
      if (!context.mounted) return null;
      showSnack(_pickerEmptyMessage(mode));
      return null;
    }
    if (!context.mounted) return null;

    return showModalBottomSheet<AssetEntity>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final height = MediaQuery.of(sheetContext).size.height * 0.8;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: assets.length,
              itemBuilder: (_, index) {
                final asset = assets[index];
                return GestureDetector(
                  onTap: () => Navigator.of(sheetContext).pop(asset),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _AssetThumbnail(asset: asset),
                        if (asset.type == AssetType.video)
                          const Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.play_circle_fill,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (mode == ChatAssetPickerMode.livePhoto)
                          const Positioned(
                            top: 6,
                            left: 6,
                            child: _AssetLiveBadge(),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  static Future<List<AssetEntity>> _filterAssetsForMode(
    List<AssetEntity> assets,
    ChatAssetPickerMode mode,
  ) async {
    if (mode == ChatAssetPickerMode.video) {
      return assets.where((asset) => asset.type == AssetType.video).toList();
    }

    final imageAssets =
        assets.where((asset) => asset.type == AssetType.image).toList();
    if (Platform.isIOS) {
      return imageAssets.where((asset) {
        final isLive = asset.isLivePhoto;
        return mode == ChatAssetPickerMode.livePhoto ? isLive : !isLive;
      }).toList();
    }
    if (Platform.isAndroid && mode == ChatAssetPickerMode.image) {
      return imageAssets;
    }

    final filtered = <AssetEntity>[];
    for (final asset in imageAssets.take(90)) {
      final isDynamic = await _isDynamicAsset(asset);
      if (mode == ChatAssetPickerMode.livePhoto && isDynamic) {
        filtered.add(asset);
      } else if (mode == ChatAssetPickerMode.image && !isDynamic) {
        filtered.add(asset);
      }
    }
    return filtered;
  }

  static Future<bool> _isDynamicAsset(AssetEntity asset) async {
    if (Platform.isIOS) {
      return asset.isLivePhoto;
    }
    if (Platform.isAndroid) {
      return LivePhotoDetector.detectMotionPhoto(asset);
    }
    return false;
  }

  static String _pickerEmptyMessage(ChatAssetPickerMode mode) {
    switch (mode) {
      case ChatAssetPickerMode.image:
        return '没有找到图片';
      case ChatAssetPickerMode.video:
        return '没有找到视频';
      case ChatAssetPickerMode.livePhoto:
        return '没有找到 Live Photo';
    }
  }
}

class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetThumbnail extends StatelessWidget {
  const _AssetThumbnail({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize(220, 220)),
      builder: (_, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const ColoredBox(color: Color(0xFFF3F4F6));
        }
        return Image.memory(
          data,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        );
      },
    );
  }
}

class _AssetLiveBadge extends StatelessWidget {
  const _AssetLiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 3.5,
            backgroundColor: Color(0xFFFF4D4F),
          ),
          SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
