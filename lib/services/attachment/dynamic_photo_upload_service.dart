import 'package:vox_flutter/models/dynamic_media_pick_result.dart';
import 'package:vox_flutter/models/attachment_upload_response.dart';
import 'package:vox_flutter/services/attachment/attachment_service.dart';

class DynamicPhotoUploadService {
  const DynamicPhotoUploadService(this._files);

  final AttachmentService _files;

  Future<AttachmentUploadResponse> upload({
    required DynamicMediaPickResult pickResult,
    required int userId,
  }) async {
    switch (pickResult.uploadMode) {
      case DynamicMediaUploadMode.livePhotoPair:
        final videoPath = pickResult.videoPath;
        if (videoPath == null || videoPath.trim().isEmpty) {
          throw Exception('Live Photo pair is missing the video path.');
        }
        return _files.uploadLivePhotoAuto(
          jpegPath: pickResult.coverPath,
          movPath: videoPath,
          userId: userId,
        );
      case DynamicMediaUploadMode.motionPhotoFile:
        return _files.uploadMotionPhotoFromPath(
          filePath: pickResult.coverPath,
          userId: userId,
        );
    }
  }
}


