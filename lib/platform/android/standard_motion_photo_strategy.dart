import 'package:dynamic_photo_chat_flutter/models/dynamic_media_pick_result.dart';
import 'package:dynamic_photo_chat_flutter/platform/android/android_dynamic_photo_resolver.dart';
import 'package:dynamic_photo_chat_flutter/utils/live_photo_detector.dart';
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
        await LivePhotoDetector.detectMotionPhotoFromPath(file.path);
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
