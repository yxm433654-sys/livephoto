class ChatMedia {
  ChatMedia({
    required this.mediaKind,
    required this.processingStatus,
    required this.resourceId,
    required this.coverResourceId,
    required this.playResourceId,
    required this.coverUrl,
    required this.playUrl,
    required this.width,
    required this.height,
    required this.duration,
    required this.aspectRatio,
    required this.sourceType,
  });

  final String? mediaKind;
  final String? processingStatus;
  final int? resourceId;
  final int? coverResourceId;
  final int? playResourceId;
  final String? coverUrl;
  final String? playUrl;
  final int? width;
  final int? height;
  final double? duration;
  final double? aspectRatio;
  final String? sourceType;

  bool get isReady => (processingStatus ?? '').toUpperCase() == 'READY';
  bool get isProcessing => (processingStatus ?? '').toUpperCase() == 'PROCESSING';

  static ChatMedia? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    int? toInt(Object? v) => v is num ? v.toInt() : null;
    double? toDouble(Object? v) => v is num ? v.toDouble() : null;

    return ChatMedia(
      mediaKind: raw['mediaKind']?.toString(),
      processingStatus: raw['processingStatus']?.toString(),
      resourceId: toInt(raw['resourceId']),
      coverResourceId: toInt(raw['coverResourceId']),
      playResourceId: toInt(raw['playResourceId']),
      coverUrl: raw['coverUrl']?.toString(),
      playUrl: raw['playUrl']?.toString(),
      width: toInt(raw['width']),
      height: toInt(raw['height']),
      duration: toDouble(raw['duration']),
      aspectRatio: toDouble(raw['aspectRatio']),
      sourceType: raw['sourceType']?.toString(),
    );
  }

  Map<String, Object?> toJson() => {
        'mediaKind': mediaKind,
        'processingStatus': processingStatus,
        'resourceId': resourceId,
        'coverResourceId': coverResourceId,
        'playResourceId': playResourceId,
        'coverUrl': coverUrl,
        'playUrl': playUrl,
        'width': width,
        'height': height,
        'duration': duration,
        'aspectRatio': aspectRatio,
        'sourceType': sourceType,
      };
}
