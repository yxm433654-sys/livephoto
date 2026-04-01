import 'package:vox_flutter/models/dynamic_media_pick_result.dart';
import 'package:vox_flutter/utils/dynamic_photo_detector.dart';
import 'package:photo_manager/photo_manager.dart';

class IosDynamicPhotoAdapter {
  const IosDynamicPhotoAdapter();

  Future<DynamicMediaPickResult?> detect(AssetEntity asset) async {
    final dynamicPhoto = await DynamicPhotoDetector.detectIosDynamicPhoto(asset);
    if (dynamicPhoto == null) {
      return null;
    }
    return DynamicMediaPickResult(
      coverPath: dynamicPhoto.imagePath,
      videoPath: dynamicPhoto.videoPath,
      uploadMode: DynamicMediaUploadMode.livePhotoPair,
      sourceType: 'iOS_LivePhoto',
    );
  }
}


