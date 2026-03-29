import 'dart:math' as math;

import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.myName,
    required this.peerName,
    required this.myAvatarUrl,
    required this.peerAvatarUrl,
    required this.onPlayVideo,
    required this.onPreviewImage,
    required this.onOpenDynamicPhoto,
  });

  final ChatMessage message;
  final bool isMine;
  final String myName;
  final String peerName;
  final String? myAvatarUrl;
  final String? peerAvatarUrl;
  final void Function(String url) onPlayVideo;
  final void Function(String url) onPreviewImage;
  final void Function(String coverUrl, String videoUrl) onOpenDynamicPhoto;

  @override
  Widget build(BuildContext context) {
    final bubbleMaxWidth =
        math.min(MediaQuery.of(context).size.width * 0.7, 320.0);
    final time = message.createdAt == null
        ? ''
        : DateFormat('HH:mm').format(message.createdAt!.toLocal());
    final mediaWidth = bubbleMaxWidth;
    final maxMediaHeight = math.min(
      MediaQuery.of(context).size.height * 0.5,
      mediaWidth * 2.5,
    );

    final avatar = _Avatar(
      name: isMine ? myName : peerName,
      avatarUrl: isMine ? myAvatarUrl : peerAvatarUrl,
      seed: isMine ? message.senderId : message.senderId,
    );

    final bubble = _content(context, mediaWidth, maxMediaHeight);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment:
          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: isMine
          ? [
              Text(time,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              const SizedBox(width: 6),
              bubble,
              const SizedBox(width: 8),
              avatar,
            ]
          : [
              avatar,
              const SizedBox(width: 8),
              bubble,
              const SizedBox(width: 6),
              Text(time,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width),
        child: row,
      ),
    );
  }

  Widget _content(
      BuildContext context, double mediaWidth, double maxMediaHeight) {
    final t = message.type.toUpperCase();
    if (t == 'TEXT') {
      return _TextBubble(text: message.content ?? '', isMine: isMine);
    }

    if (t == 'IMAGE') {
      final url = message.coverUrl;
      if (url == null || url.isEmpty) return const Text('图片不可用');
      final resolved = _resolveUrl(context, url);
      return GestureDetector(
        onTap: () => onPreviewImage(resolved),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: mediaWidth,
              maxHeight: maxMediaHeight,
            ),
            child: Image.network(
              resolved,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Colors.black12),
            ),
          ),
        ),
      );
    }

    if (t == 'VIDEO') {
      final video = message.videoUrl;
      final cover = message.coverUrl;
      if ((video == null || video.isEmpty) &&
          (cover == null || cover.isEmpty)) {
        return const Text('视频不可用');
      }
      return _videoPreview(
        mediaWidth: mediaWidth,
        maxMediaHeight: maxMediaHeight,
        videoUrl:
            video == null || video.isEmpty ? null : _resolveUrl(context, video),
        coverUrl:
            cover == null || cover.isEmpty ? null : _resolveUrl(context, cover),
      );
    }

    if (t == 'DYNAMIC_PHOTO') {
      final cover = message.coverUrl;
      final video = message.videoUrl;
      if (cover == null || cover.isEmpty || video == null || video.isEmpty) {
        return const Text('动态图片不可用');
      }
      final resolvedCover = _resolveUrl(context, cover);
      final resolvedVideo = _resolveUrl(context, video);
      return GestureDetector(
        onTap: () => onOpenDynamicPhoto(resolvedCover, resolvedVideo),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: mediaWidth,
              maxHeight: maxMediaHeight,
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.center,
              children: [
                Image.network(
                  resolvedCover,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Colors.black12),
                ),
                const Positioned(
                  right: 6,
                  top: 6,
                  child: Icon(
                    Icons.motion_photos_on,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Text(message.content ?? t);
  }

  Widget _videoPreview({
    required double mediaWidth,
    required double maxMediaHeight,
    required String? videoUrl,
    required String? coverUrl,
  }) {
    return GestureDetector(
      onTap: videoUrl == null ? null : () => onPlayVideo(videoUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: mediaWidth,
            maxHeight: maxMediaHeight,
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.center,
            children: [
              if (coverUrl == null)
                SizedBox(
                  width: mediaWidth,
                  height: math.min(mediaWidth * 9 / 16, maxMediaHeight),
                  child: const ColoredBox(color: Colors.black12),
                )
              else
                Image.network(
                  coverUrl,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Colors.black12),
                ),
              Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 28),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _resolveUrl(BuildContext context, String url) {
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      return url;
    }
    final base = Uri.parse(context.read<AppState>().apiBaseUrl);
    final path = url.startsWith('/') ? url : '/$url';
    return base.replace(path: path, query: null, fragment: null).toString();
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.text, required this.isMine});

  final String text;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final bg = isMine ? const Color(0xFF95EC69) : Colors.white;
    final border = isMine
        ? Border.all(color: Colors.transparent)
        : Border.all(color: const Color(0xFFE5E7EB));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.of(context).size.width * 0.7, 320.0),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, color: Color(0xFF111827)),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(
      {required this.name, required this.avatarUrl, required this.seed});

  final String name;
  final String? avatarUrl;
  final int seed;

  Color _color() {
    final colors = <Color>[
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEF4444),
    ];
    return colors[seed.abs() % colors.length];
  }

  String _initial() {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t.characters.first;
  }

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: NetworkImage(url),
        backgroundColor: const Color(0xFFE5E7EB),
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: _color(),
      child: Text(
        _initial(),
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}
