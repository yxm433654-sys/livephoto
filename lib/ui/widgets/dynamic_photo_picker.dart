import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// 动态照片选择器 — 从相册中选择一张图片（支持 Live Photo / Motion Photo）
class DynamicPhotoPickerDialog extends StatefulWidget {
  const DynamicPhotoPickerDialog({super.key});

  /// 显示选择器，返回选中的 AssetEntity 或 null
  static Future<AssetEntity?> pick(BuildContext context) {
    return showModalBottomSheet<AssetEntity>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const DynamicPhotoPickerDialog(),
    );
  }

  @override
  State<DynamicPhotoPickerDialog> createState() =>
      _DynamicPhotoPickerDialogState();
}

class _DynamicPhotoPickerDialogState extends State<DynamicPhotoPickerDialog> {
  List<AssetEntity> _assets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '需要相册访问权限';
        });
      }
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
    );
    if (albums.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '未找到相册';
        });
      }
      return;
    }

    final recent = albums.first;
    final count = await recent.assetCountAsync;
    final end = count > 200 ? 200 : count;
    final assets = await recent.getAssetListRange(start: 0, end: end);

    if (mounted) {
      setState(() {
        _assets = assets;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text(
                  '选择动态照片',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_assets.isEmpty) {
      return const Center(child: Text('相册中没有图片'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _assets.length,
      itemBuilder: (ctx, idx) =>
          _AssetThumb(asset: _assets[idx], onTap: () {
            Navigator.pop(context, _assets[idx]);
          }),
    );
  }
}

class _AssetThumb extends StatefulWidget {
  const _AssetThumb({required this.asset, required this.onTap});

  final AssetEntity asset;
  final VoidCallback onTap;

  @override
  State<_AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<_AssetThumb> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final data = await widget.asset
        .thumbnailDataWithSize(const ThumbnailSize(200, 200));
    if (mounted) setState(() => _thumb = data);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: _thumb == null
          ? Container(color: Colors.grey[300])
          : Image.memory(_thumb!, fit: BoxFit.cover),
    );
  }
}
