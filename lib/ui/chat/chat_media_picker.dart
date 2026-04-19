import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:vox_flutter/utils/dynamic_photo_detector.dart';

enum ChatAttachAction {
  media,
  file,
}

enum ChatPickedAssetKind {
  image,
  video,
  dynamicPhoto,
}

class ChatPickedAsset {
  const ChatPickedAsset({
    required this.asset,
    required this.kind,
  });

  final AssetEntity asset;
  final ChatPickedAssetKind kind;
}

class ChatMediaPicker {
  const ChatMediaPicker._();

  static const int imageMaxBytes = 20 * 1024 * 1024;
  static const int videoMaxBytes = 256 * 1024 * 1024;
  static const int maxSelectionCount = 9;

  static Future<ChatAttachAction?> showAttachMenu(BuildContext context) {
    return showModalBottomSheet<ChatAttachAction>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '发送内容',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '图片建议不超过 20MB。视频、动态照片和文件建议不超过 256MB。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _AttachTile(
                      icon: Icons.photo_library_outlined,
                      label: '媒体',
                      color: const Color(0xFFE0F2FE),
                      iconColor: const Color(0xFF0284C7),
                      onTap: () => Navigator.of(sheetContext).pop(ChatAttachAction.media),
                    ),
                    const SizedBox(width: 14),
                    _AttachTile(
                      icon: Icons.attach_file_rounded,
                      label: '文件',
                      color: const Color(0xFFF3E8FF),
                      iconColor: const Color(0xFF7C3AED),
                      onTap: () => Navigator.of(sheetContext).pop(ChatAttachAction.file),
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

  static Future<List<ChatPickedAsset>> pickMediaAssets({
    required BuildContext context,
    required void Function(String message) showSnack,
  }) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      showSnack('请先允许访问媒体库。');
      return const <ChatPickedAsset>[];
    }
    if (!context.mounted) {
      return const <ChatPickedAsset>[];
    }

    final result = await showModalBottomSheet<List<ChatPickedAsset>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final height = MediaQuery.of(sheetContext).size.height * 0.78;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: _MixedAssetPickerSheet(showSnack: showSnack),
          ),
        );
      },
    );
    return result ?? const <ChatPickedAsset>[];
  }

  static Future<List<ChatPickedAsset>> _loadAssets() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(sizeConstraint: SizeConstraint()),
        videoOption: const FilterOption(sizeConstraint: SizeConstraint()),
      ),
    );
    if (paths.isEmpty) {
      return const <ChatPickedAsset>[];
    }

    final rawAssets = await paths.first.getAssetListPaged(page: 0, size: 100);
    final items = <ChatPickedAsset>[];
    for (final asset in rawAssets) {
      final kind = await _resolveKind(asset);
      if (kind == null) {
        continue;
      }
      items.add(ChatPickedAsset(asset: asset, kind: kind));
    }
    return items;
  }

  static Future<ChatPickedAssetKind?> _resolveKind(AssetEntity asset) async {
    if (asset.type == AssetType.video) {
      return ChatPickedAssetKind.video;
    }
    if (asset.type != AssetType.image) {
      return null;
    }

    if (Platform.isIOS) {
      return asset.isLivePhoto
          ? ChatPickedAssetKind.dynamicPhoto
          : ChatPickedAssetKind.image;
    }

    if (Platform.isAndroid) {
      return ChatPickedAssetKind.image;
    }

    return ChatPickedAssetKind.image;
  }
}

class _MixedAssetPickerSheet extends StatefulWidget {
  const _MixedAssetPickerSheet({
    required this.showSnack,
  });

  final void Function(String message) showSnack;

  @override
  State<_MixedAssetPickerSheet> createState() => _MixedAssetPickerSheetState();
}

class _MixedAssetPickerSheetState extends State<_MixedAssetPickerSheet> {
  final List<ChatPickedAsset> _selected = <ChatPickedAsset>[];
  final Map<String, Future<Uint8List?>> _thumbnailFutures =
      <String, Future<Uint8List?>>{};
  final Map<String, ChatPickedAssetKind> _resolvedKinds =
      <String, ChatPickedAssetKind>{};
  final Set<String> _resolvingAssetIds = <String>{};
  late final Future<List<ChatPickedAsset>> _assetsFuture;

  @override
  void initState() {
    super.initState();
    _assetsFuture = ChatMediaPicker._loadAssets();
  }

  Future<Uint8List?> _thumbnailFuture(AssetEntity asset) {
    return _thumbnailFutures.putIfAbsent(
      asset.id,
      () => asset.thumbnailDataWithSize(const ThumbnailSize(160, 160)),
    );
  }

  bool _isSelected(ChatPickedAsset asset) {
    return _selected.any((item) => item.asset.id == asset.asset.id);
  }

  ChatPickedAssetKind _effectiveKind(ChatPickedAsset asset) {
    return _resolvedKinds[asset.asset.id] ?? asset.kind;
  }

  Future<ChatPickedAsset> _resolveSelectionKind(ChatPickedAsset asset) async {
    final cachedKind = _resolvedKinds[asset.asset.id];
    if (cachedKind != null) {
      return ChatPickedAsset(asset: asset.asset, kind: cachedKind);
    }
    if (!Platform.isAndroid || asset.kind != ChatPickedAssetKind.image) {
      return asset;
    }

    final isMotionPhoto =
        await DynamicPhotoDetector.detectAndroidMotionPhoto(asset.asset);
    final kind = isMotionPhoto
        ? ChatPickedAssetKind.dynamicPhoto
        : ChatPickedAssetKind.image;
    _resolvedKinds[asset.asset.id] = kind;
    return ChatPickedAsset(asset: asset.asset, kind: kind);
  }

  Future<void> _toggle(ChatPickedAsset asset) async {
    final existingIndex = _selected.indexWhere(
      (item) => item.asset.id == asset.asset.id,
    );
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

    if (_resolvingAssetIds.contains(asset.asset.id)) {
      return;
    }

    setState(() {
      _resolvingAssetIds.add(asset.asset.id);
    });

    final resolvedAsset = await _resolveSelectionKind(asset);
    if (!mounted) {
      return;
    }

    final latestIndex = _selected.indexWhere(
      (item) => item.asset.id == asset.asset.id,
    );
    setState(() {
      _resolvingAssetIds.remove(asset.asset.id);
      if (latestIndex < 0) {
        _selected.add(resolvedAsset);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChatPickedAsset>>(
      future: _assetsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final assets = snapshot.data ?? const <ChatPickedAsset>[];
        if (assets.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) {
              return;
            }
            widget.showSnack('没有找到可发送的图片、视频或动态照片。');
          });
          return const Center(
            child: Text(
              '没有找到可发送的图片、视频或动态照片。',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '图片、视频和动态照片混合展示。点击选择后直接发送，最多 9 项。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
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
                  final item = assets[index];
                  final effectiveKind = _effectiveKind(item);
                  final selectedIndex = _selected.indexWhere(
                    (selected) => selected.asset.id == item.asset.id,
                  );
                  return GestureDetector(
                    onTap: () {
                      _toggle(item);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _AssetThumbnail(
                            future: _thumbnailFuture(item.asset),
                          ),
                          if (effectiveKind == ChatPickedAssetKind.video)
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
                          if (effectiveKind == ChatPickedAssetKind.dynamicPhoto)
                            const Positioned(
                              top: 6,
                              left: 6,
                              child: _AssetLiveBadge(),
                            ),
                          if (_resolvingAssetIds.contains(item.asset.id))
                            Container(
                              color: Colors.black.withOpacity(0.18),
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          if (_isSelected(item))
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
        width: 80,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: iconColor, size: 28),
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
  const _AssetThumbnail({required this.future});

  final Future<Uint8List?> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: future,
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
