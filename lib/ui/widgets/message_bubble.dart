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
    this.videoCoverWaitProgress,
    this.videoAspectRatio,
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
  final double? videoCoverWaitProgress;
  final double? videoAspectRatio;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    // 与微信会话内图片/视频接近：宽度约半屏、上限 240dp；竖图高度按宽高比收紧
    final mediaWidth = math.min(screenW * 0.48, 240.0);
    final maxMediaHeight = math.min(screenH * 0.36, mediaWidth * 1.75);
    final time = message.createdAt == null
        ? ''
        : DateFormat('HH:mm').format(message.createdAt!.toLocal());

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
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheW = math.max(1, (mediaWidth * dpr).round());
    final t = message.type.toUpperCase();
    if (t == 'TEXT') {
      return _TextBubble(text: message.content ?? '', isMine: isMine);
    }

    if (t == 'IMAGE') {
      final url = message.coverUrl;
      if (url == null || url.trim().isEmpty) return const Text('图片不可用');
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
            child: _networkImageWithProgress(
              url: resolved,
              cacheWidth: cacheW,
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
            cover == null || cover.trim().isEmpty ? null : _resolveUrl(context, cover),
        coverWaitProgress: videoCoverWaitProgress,
        videoAspectRatio: videoAspectRatio,
      );
    }

    if (t == 'DYNAMIC_PHOTO') {
      final cover = message.coverUrl;
      final video = message.videoUrl;
      if (cover == null || cover.trim().isEmpty) {
        return const Text('动态图片不可用');
      }
      final resolvedCover = _resolveUrl(context, cover);
      final resolvedVideo =
          (video == null || video.trim().isEmpty)
              ? null
              : _resolveUrl(context, video);
      return GestureDetector(
        onTap: resolvedVideo == null
            ? null
            : () => onOpenDynamicPhoto(resolvedCover, resolvedVideo),
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
                _networkImageWithProgress(
                  url: resolvedCover,
                  cacheWidth: cacheW,
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
    required double? coverWaitProgress,
    required double? videoAspectRatio,
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
                Builder(builder: (_) {
                  // 占位期间封面不存在：用视频宽高比推导出等比占位尺寸，避免“比例被写死导致看起来变形”。
                  final ar = videoAspectRatio ?? 9 / 16;
                  final preferredH = mediaWidth / ar;
                  final actualH =
                      preferredH <= maxMediaHeight ? preferredH : maxMediaHeight;
                  final actualW = actualH * ar;

                  return SizedBox(
                    width: actualW,
                    height: actualH,
                    child: const ColoredBox(color: Colors.black12),
                  );
                })
              else
                _networkImageWithProgress(
                  url: coverUrl,
                  cacheWidth: mediaWidth.round(),
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
              if (coverUrl == null)
                Positioned(
                  right: 8,
                  top: 8,
                  child: SizedBox(
                    width: 68,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: coverWaitProgress?.clamp(0, 1),
                          minHeight: 4,
                          backgroundColor: Colors.black12,
                        ),
                        if (coverWaitProgress != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${(coverWaitProgress * 100).clamp(0, 100).round()}%',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _networkImageWithProgress({
    required String url,
    required int cacheWidth,
  }) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      // 只设置 cacheWidth，避免 cacheWidth+cacheHeight 同时设定导致解码尺寸被拉伸。
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.low,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;

        final expected = loadingProgress.expectedTotalBytes;
        final loaded = loadingProgress.cumulativeBytesLoaded;
        final value =
            (expected != null && expected > 0) ? loaded / expected : null;
        final pct = value == null ? null : (value * 100).clamp(0, 100);

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black12),
            child,
            Positioned(
              left: 8,
              right: 8,
              bottom: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: value,
                    minHeight: 3,
                    backgroundColor: Colors.black12,
                  ),
                  if (pct != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${pct.round()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
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
