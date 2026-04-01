import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:vox_flutter/utils/dynamic_photo_detector.dart';

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

  static const int imageMaxBytes = 20 * 1024 * 1024;
  static const int videoMaxBytes = 256 * 1024 * 1024;
  static const int maxSelectionCount = 9;

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
                const SizedBox(height: 6),
                const Text(
                  '图片和视频最多可选 9 项；图片单张建议不超过 20MB，视频和动态照片建议不超过 256MB。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    height: 1.4,
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
                      onTap: () => Navigator.of(sheetContext).pop(
                        ChatAttachAction.galleryImage,
                      ),
                    ),
                    _AttachTile(
                      icon: Icons.smart_display_outlined,
                      label: '视频',
                      color: const Color(0xFFDCFCE7),
                      iconColor: const Color(0xFF16A34A),
                      onTap: () => Navigator.of(sheetContext).pop(
                        ChatAttachAction.galleryVideo,
                      ),
                    ),
                    _AttachTile(
                      icon: Icons.motion_photos_on_outlined,
                      label: '动态照片',
                      color: const Color(0xFFFCE7F3),
                      iconColor: const Color(0xFFDB2777),
                      onTap: () => Navigator.of(sheetContext).pop(
                        ChatAttachAction.livePhoto,
                      ),
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

  static Future<List<AssetEntity>> pickAssets({
    required BuildContext context,
    required ChatAssetPickerMode mode,
    required void Function(String message) showSnack,
  }) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      showSnack('请先允许访问媒体库。');
      return const <AssetEntity>[];
    }
    if (!context.mounted) {
      return const <AssetEntity>[];
    }

    final allowMultiple = mode != ChatAssetPickerMode.livePhoto;
    final result = await showModalBottomSheet<List<AssetEntity>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final height = MediaQuery.of(sheetContext).size.height * 0.76;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: _AssetPickerSheet(
              mode: mode,
              allowMultiple: allowMultiple,
              showSnack: showSnack,
            ),
          ),
        );
      },
    );
    return result ?? const <AssetEntity>[];
  }

  static Future<AssetEntity?> pickAsset({
    required BuildContext context,
    required ChatAssetPickerMode mode,
    required void Function(String message) showSnack,
  }) async {
    final assets = await pickAssets(
      context: context,
      mode: mode,
      showSnack: showSnack,
    );
    if (assets.isEmpty) {
      return null;
    }
    return assets.first;
  }

  static Future<List<AssetEntity>> _loadAssets(ChatAssetPickerMode mode) async {
    final paths = await PhotoManager.getAssetPathList(
      type: mode == ChatAssetPickerMode.video
          ? RequestType.video
          : RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(sizeConstraint: SizeConstraint()),
        videoOption: const FilterOption(sizeConstraint: SizeConstraint()),
      ),
    );
    if (paths.isEmpty) {
      return const <AssetEntity>[];
    }

    final rawAssets = await paths.first.getAssetListPaged(page: 0, size: 80);
    return _filterAssetsForMode(rawAssets, mode);
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

    final candidates = imageAssets.take(40).toList();
    final detected = await Future.wait(
      candidates.map((asset) async => MapEntry(asset, await _isDynamicAsset(asset))),
    );

    final filtered = <AssetEntity>[];
    for (final entry in detected) {
      if (mode == ChatAssetPickerMode.livePhoto && entry.value) {
        filtered.add(entry.key);
      } else if (mode == ChatAssetPickerMode.image && !entry.value) {
        filtered.add(entry.key);
      }
    }
    return filtered;
  }

  static Future<bool> _isDynamicAsset(AssetEntity asset) async {
    if (Platform.isIOS) {
      return asset.isLivePhoto;
    }
    if (Platform.isAndroid) {
      return DynamicPhotoDetector.detectAndroidMotionPhoto(asset);
    }
    return false;
  }

  static String pickerEmptyMessage(ChatAssetPickerMode mode) {
    switch (mode) {
      case ChatAssetPickerMode.image:
        return '没有找到图片。';
      case ChatAssetPickerMode.video:
        return '没有找到视频。';
      case ChatAssetPickerMode.livePhoto:
        return '没有找到动态照片。';
    }
  }

  static String pickerHint(ChatAssetPickerMode mode) {
    switch (mode) {
      case ChatAssetPickerMode.image:
        return '可多选，最多 9 张，单张建议不超过 20MB';
      case ChatAssetPickerMode.video:
        return '可多选，最多 9 个，单个视频建议不超过 256MB';
      case ChatAssetPickerMode.livePhoto:
        return '动态照片建议不超过 256MB';
    }
  }
}

class _AssetPickerSheet extends StatefulWidget {
  const _AssetPickerSheet({
    required this.mode,
    required this.allowMultiple,
    required this.showSnack,
  });

  final ChatAssetPickerMode mode;
  final bool allowMultiple;
  final void Function(String message) showSnack;

  @override
  State<_AssetPickerSheet> createState() => _AssetPickerSheetState();
}

class _AssetPickerSheetState extends State<_AssetPickerSheet> {
  final List<AssetEntity> _selected = <AssetEntity>[];

  bool _isSelected(AssetEntity asset) {
    return _selected.any((item) => item.id == asset.id);
  }

  void _toggle(AssetEntity asset) {
    if (!widget.allowMultiple) {
      Navigator.of(context).pop(<AssetEntity>[asset]);
      return;
    }

    final existingIndex = _selected.indexWhere((item) => item.id == asset.id);
    if (existingIndex >= 0) {
      setState(() {
        _selected.removeAt(existingIndex);
      });
      return;
    }

    if (_selected.length >= ChatMediaPicker.maxSelectionCount) {
      widget.showSnack('最多只能选择 ${ChatMediaPicker.maxSelectionCount} 项。');
      return;
    }

    setState(() {
      _selected.add(asset);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AssetEntity>>(
      future: ChatMediaPicker._loadAssets(widget.mode),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final assets = snapshot.data ?? const <AssetEntity>[];
        if (assets.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) {
              return;
            }
            widget.showSnack(ChatMediaPicker.pickerEmptyMessage(widget.mode));
          });
          return Center(
            child: Text(
              ChatMediaPicker.pickerEmptyMessage(widget.mode),
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ChatMediaPicker.pickerHint(widget.mode),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  if (widget.allowMultiple)
                    FilledButton.tonal(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(_selected),
                      child: Text('发送 ${_selected.length} 项'),
                    ),
                ],
              ),
            ),
            Expanded(
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
                  final selectedIndex = _selected.indexWhere(
                    (item) => item.id == asset.id,
                  );
                  return GestureDetector(
                    onTap: () => _toggle(asset),
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
                          if (widget.mode == ChatAssetPickerMode.livePhoto)
                            const Positioned(
                              top: 6,
                              left: 6,
                              child: _AssetLiveBadge(),
                            ),
                          if (widget.allowMultiple && _isSelected(asset))
                            Positioned(
                              top: 6,
                              right: 6,
                              child: _SelectedBadge(index: selectedIndex + 1),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
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
      future: asset.thumbnailDataWithSize(const ThumbnailSize(160, 160)),
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

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF10B981),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        '$index',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
