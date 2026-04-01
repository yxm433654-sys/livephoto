import 'package:vox_flutter/models/dynamic_media_pick_result.dart';
import 'package:vox_flutter/platform/android/standard_motion_photo_strategy.dart';
import 'package:vox_flutter/platform/android/unsupported_dynamic_photo_strategy.dart';
import 'package:photo_manager/photo_manager.dart';

class AndroidDynamicPhotoResolver {
  const AndroidDynamicPhotoResolver();

  Future<DynamicMediaPickResult?> resolve(AssetEntity asset) async {
    const strategies = <AndroidDynamicPhotoStrategy>[
      StandardMotionPhotoStrategy(),
      UnsupportedDynamicPhotoStrategy(),
    ];

    for (final strategy in strategies) {
      final result = await strategy.detect(asset);
      if (result != null) {
        return result;
      }
    }
    return null;
  }
}

abstract class AndroidDynamicPhotoStrategy {
  const AndroidDynamicPhotoStrategy();

  Future<DynamicMediaPickResult?> detect(AssetEntity asset);
}
