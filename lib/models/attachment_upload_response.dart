class AttachmentUploadResponse {
  AttachmentUploadResponse({
    required this.fileId,
    required this.coverId,
    required this.videoId,
    required this.url,
    required this.coverUrl,
    required this.videoUrl,
    required this.fileType,
    required this.sourceType,
    required this.originalName,
    required this.mimeType,
    required this.size,
    required this.width,
    required this.height,
    required this.duration,
    required this.verified,
    required this.videoOffset,
  });

  final int? fileId;
  final int? coverId;
  final int? videoId;
  final String? url;
  final String? coverUrl;
  final String? videoUrl;
  final String? fileType;
  final String? sourceType;
  final String? originalName;
  final String? mimeType;
  final int? size;
  final int? width;
  final int? height;
  final double? duration;
  final bool? verified;
  final int? videoOffset;

  static AttachmentUploadResponse fromJson(Object? raw) {
    final json = raw as Map<String, dynamic>;
    int? toInt(Object? v) => v is num ? v.toInt() : null;
    double? toDouble(Object? v) => v is num ? v.toDouble() : null;

    return AttachmentUploadResponse(
      fileId: toInt(json['fileId']),
      coverId: toInt(json['coverId']),
      videoId: toInt(json['videoId']),
      url: json['url']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      videoUrl: json['videoUrl']?.toString(),
      fileType: json['fileType']?.toString(),
      sourceType: json['sourceType']?.toString(),
      originalName: json['originalName']?.toString(),
      mimeType: json['mimeType']?.toString(),
      size: toInt(json['size']),
      width: toInt(json['width']),
      height: toInt(json['height']),
      duration: toDouble(json['duration']),
      verified: json['verified'] is bool ? json['verified'] as bool : null,
      videoOffset: toInt(json['videoOffset']),
    );
  }
}
