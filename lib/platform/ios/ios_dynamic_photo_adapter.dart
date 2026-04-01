import 'package:dynamic_photo_chat_flutter/models/dynamic_media_pick_result.dart';
import 'package:dynamic_photo_chat_flutter/utils/live_photo_detector.dart';
import 'package:photo_manager/photo_manager.dart';

class IosDynamicPhotoAdapter {
  const IosDynamicPhotoAdapter();

  Future<DynamicMediaPickResult?> detect(AssetEntity asset) async {
    final live = await LivePhotoDetector.detectLivePhoto(asset);
    if (live == null) {
      return null;
    }
    return DynamicMediaPickResult(
      coverPath: live.imagePath,
      videoPath: live.videoPath,
      uploadMode: DynamicMediaUploadMode.livePhotoPair,
      sourceType: 'iOS_LivePhoto',
    );
  }
}
