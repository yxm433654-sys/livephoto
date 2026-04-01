import 'dart:io';

import 'package:vox_flutter/models/dynamic_media_pick_result.dart';
import 'package:vox_flutter/platform/android/android_dynamic_photo_adapter.dart';
import 'package:vox_flutter/platform/ios/ios_dynamic_photo_adapter.dart';
import 'package:photo_manager/photo_manager.dart';

class DynamicPhotoAdapter {
  const DynamicPhotoAdapter();

  Future<DynamicMediaPickResult?> detect(AssetEntity asset) async {
    if (Platform.isIOS) {
      return const IosDynamicPhotoAdapter().detect(asset);
    }
    if (Platform.isAndroid) {
      return const AndroidDynamicPhotoAdapter().detect(asset);
    }
    return null;
  }
}
