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
