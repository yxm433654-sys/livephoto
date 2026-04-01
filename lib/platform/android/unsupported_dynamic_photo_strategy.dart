import 'package:dynamic_photo_chat_flutter/models/dynamic_media_pick_result.dart';
import 'package:dynamic_photo_chat_flutter/platform/android/android_dynamic_photo_resolver.dart';
import 'package:photo_manager/photo_manager.dart';

class UnsupportedDynamicPhotoStrategy extends AndroidDynamicPhotoStrategy {
  const UnsupportedDynamicPhotoStrategy();

  @override
  Future<DynamicMediaPickResult?> detect(AssetEntity asset) async {
    return null;
  }
}
