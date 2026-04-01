import 'package:vox_flutter/models/dynamic_media_pick_result.dart';
import 'package:vox_flutter/platform/android/android_dynamic_photo_resolver.dart';
import 'package:vox_flutter/utils/dynamic_photo_detector.dart';
import 'package:photo_manager/photo_manager.dart';

class StandardMotionPhotoStrategy extends AndroidDynamicPhotoStrategy {
  const StandardMotionPhotoStrategy();

  @override
  Future<DynamicMediaPickResult?> detect(AssetEntity asset) async {
    final file = await asset.file;
    if (file == null) {
      return null;
    }
    final isMotionPhoto =
        await DynamicPhotoDetector.detectAndroidMotionPhotoFromPath(file.path);
    if (!isMotionPhoto) {
      return null;
    }
    return DynamicMediaPickResult(
      coverPath: file.path,
      uploadMode: DynamicMediaUploadMode.motionPhotoFile,
      sourceType: 'Android_MotionPhoto',
    );
  }
}

