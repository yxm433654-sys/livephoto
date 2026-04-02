import 'package:vox_flutter/models/chat_media.dart';

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.content,
    required this.resourceId,
    required this.videoResourceId,
    required this.coverUrl,
    required this.videoUrl,
    required this.media,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final int senderId;
  final int receiverId;
  final String type;
  final String? content;
  final int? resourceId;
  final int? videoResourceId;
  final String? coverUrl;
  final String? videoUrl;
  final ChatMedia? media;
  final String? status;
  final DateTime? createdAt;

  String? get resolvedCoverUrl => media?.coverUrl ?? coverUrl;
  String? get resolvedPlayUrl => media?.playUrl ?? videoUrl;
  bool get isSending => (status ?? '').toUpperCase() == 'SENDING';
  bool get isFailed => (status ?? '').toUpperCase() == 'FAILED';

  ChatMessage copyWith({
    int? id,
    int? senderId,
    int? receiverId,
    String? type,
    Object? content = _unset,
    Object? resourceId = _unset,
    Object? videoResourceId = _unset,
    Object? coverUrl = _unset,
    Object? videoUrl = _unset,
    Object? media = _unset,
    Object? status = _unset,
    Object? createdAt = _unset,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      type: type ?? this.type,
      content: identical(content, _unset) ? this.content : content as String?,
      resourceId: identical(resourceId, _unset)
          ? this.resourceId
          : resourceId as int?,
      videoResourceId: identical(videoResourceId, _unset)
          ? this.videoResourceId
          : videoResourceId as int?,
      coverUrl: identical(coverUrl, _unset) ? this.coverUrl : coverUrl as String?,
      videoUrl: identical(videoUrl, _unset) ? this.videoUrl : videoUrl as String?,
      media: identical(media, _unset) ? this.media : media as ChatMedia?,
      status: identical(status, _unset) ? this.status : status as String?,
      createdAt: identical(createdAt, _unset)
          ? this.createdAt
          : createdAt as DateTime?,
    );
  }

  static ChatMessage fromJson(Object? raw) {
    final json = raw as Map<String, dynamic>;
    return ChatMessage(
      id: (json['id'] as num).toInt(),
      senderId: (json['senderId'] as num).toInt(),
      receiverId: (json['receiverId'] as num).toInt(),
      type: json['type']?.toString() ?? 'TEXT',
      content: json['content']?.toString(),
      resourceId: json['resourceId'] is num
          ? (json['resourceId'] as num).toInt()
          : null,
      videoResourceId: json['videoResourceId'] is num
          ? (json['videoResourceId'] as num).toInt()
          : null,
      coverUrl: json['coverUrl']?.toString(),
      videoUrl: json['videoUrl']?.toString(),
      media: ChatMedia.fromJson(json['media']),
      status: json['status']?.toString(),
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'])
          : null,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'senderId': senderId,
        'receiverId': receiverId,
        'type': type,
        'content': content,
        'resourceId': resourceId,
        'videoResourceId': videoResourceId,
        'coverUrl': coverUrl,
        'videoUrl': videoUrl,
        'media': media?.toJson(),
        'status': status,
        'createdAt': createdAt?.toIso8601String(),
      };
}

const Object _unset = Object();
