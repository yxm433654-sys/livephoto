import 'package:vox_flutter/models/dynamic_media_pick_result.dart';
import 'package:vox_flutter/platform/android/android_dynamic_photo_resolver.dart';
import 'package:photo_manager/photo_manager.dart';

class AndroidDynamicPhotoAdapter {
  const AndroidDynamicPhotoAdapter();

  Future<DynamicMediaPickResult?> detect(AssetEntity asset) {
    return const AndroidDynamicPhotoResolver().resolve(asset);
  }
}
