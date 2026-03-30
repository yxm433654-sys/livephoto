import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dynamic_photo_chat_flutter/models/chat_media.dart';
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
    this.localCoverBytes,
    this.localCoverPath,
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
  final Uint8List? localCoverBytes;
  final String? localCoverPath;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    final mediaWidth = math.min(screenW * 0.48, 240.0);
    final maxMediaHeight = math.min(screenH * 0.36, mediaWidth * 1.75);
    final time = message.createdAt == null
        ? ''
        : DateFormat('HH:mm').format(message.createdAt!.toLocal());

    final avatar = _Avatar(
      name: isMine ? myName : peerName,
      avatarUrl: isMine ? myAvatarUrl : peerAvatarUrl,
      seed: message.senderId,
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
    final media = message.media;

    if (t == 'TEXT') {
      return _TextBubble(text: message.content ?? '', isMine: isMine);
    }

    if (t == 'IMAGE') {
      final localBytes = localCoverBytes;
      final localPath = localCoverPath;
      if (localBytes != null) {
        return GestureDetector(
          onTap: () {},
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: mediaWidth,
                maxHeight: maxMediaHeight,
              ),
              child: Image.memory(localBytes, fit: BoxFit.cover),
            ),
          ),
        );
      }
      if (localPath != null && localPath.trim().isNotEmpty) {
        return GestureDetector(
          onTap: () {},
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: mediaWidth,
                maxHeight: maxMediaHeight,
              ),
              child: Image.file(File(localPath), fit: BoxFit.cover),
            ),
          ),
        );
      }

      final url = media?.coverUrl ?? message.coverUrl;
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
            child: _networkImage(
              url: resolved,
              cacheWidth: cacheW,
            ),
          ),
        ),
      );
    }

    if (t == 'VIDEO') {
      final video = media?.playUrl ?? message.videoUrl;
      final cover = media?.coverUrl ?? message.coverUrl;
      if ((video == null || video.isEmpty) &&
          (cover == null || cover.isEmpty)) {
        return const Text('视频不可用');
      }

      ImageProvider? localProvider;
      if (localCoverBytes != null) {
        localProvider = MemoryImage(localCoverBytes!);
      } else if (localCoverPath != null && localCoverPath!.trim().isNotEmpty) {
        localProvider = FileImage(File(localCoverPath!));
      }

      return _videoPreview(
        mediaWidth: mediaWidth,
        maxMediaHeight: maxMediaHeight,
        videoUrl: video == null || video.isEmpty ? null : _resolveUrl(context, video),
        coverUrl: localProvider != null
            ? null
            : (cover == null || cover.trim().isEmpty
                ? null
                : _resolveUrl(context, cover)),
        localCoverProvider: localProvider,
        processingStatus: media?.processingStatus,
        aspectRatio: _resolveAspectRatio(media, fallback: 9 / 16),
      );
    }

    if (t == 'DYNAMIC_PHOTO') {
      final cover = media?.coverUrl ?? message.coverUrl;
      final video = media?.playUrl ?? message.videoUrl;
      final processingStatus = media?.processingStatus;

      Widget coverWidget;
      if (localCoverBytes != null) {
        coverWidget = Image.memory(localCoverBytes!, fit: BoxFit.cover);
      } else if (localCoverPath != null && localCoverPath!.trim().isNotEmpty) {
        coverWidget = Image.file(File(localCoverPath!), fit: BoxFit.cover);
      } else if (cover != null && cover.trim().isNotEmpty) {
        coverWidget = _networkImage(
          url: _resolveUrl(context, cover),
          cacheWidth: cacheW,
        );
      } else {
        coverWidget = _mediaPlaceholder(
          mediaWidth: mediaWidth,
          maxMediaHeight: maxMediaHeight,
          aspectRatio: _resolveAspectRatio(media, fallback: 3 / 4),
        );
      }

      final resolvedVideo = (video == null || video.trim().isEmpty)
          ? null
          : _resolveUrl(context, video);

      return GestureDetector(
        onTap: resolvedVideo == null
            ? null
            : () {
                final resolvedCover = (cover == null || cover.trim().isEmpty)
                    ? ''
                    : _resolveUrl(context, cover);
                onOpenDynamicPhoto(resolvedCover, resolvedVideo);
              },
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
                coverWidget,
                if ((processingStatus ?? '').toUpperCase() == 'PROCESSING')
                  _statusOverlay('处理中'),
                const Positioned(
                  right: 8,
                  top: 8,
                  child: _LiveBadge(),
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
    required ImageProvider? localCoverProvider,
    required String? processingStatus,
    required double aspectRatio,
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
              if (localCoverProvider != null)
                Image(
                  image: localCoverProvider,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                )
              else if (coverUrl == null)
                _mediaPlaceholder(
                  mediaWidth: mediaWidth,
                  maxMediaHeight: maxMediaHeight,
                  aspectRatio: aspectRatio,
                )
              else
                _networkImage(
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
              if ((processingStatus ?? '').toUpperCase() == 'PROCESSING')
                Positioned(bottom: 8, child: _pill('处理中')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _networkImage({
    required String url,
    required int cacheWidth,
  }) {
    return CachedNetworkImage(
      imageUrl: url,
      memCacheWidth: cacheWidth,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: const Duration(milliseconds: 120),
      imageBuilder: (context, imageProvider) => Image(
        image: imageProvider,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.low,
      ),
      placeholder: (_, __) => const ColoredBox(color: Colors.black12),
      errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black12),
    );
  }

  Widget _mediaPlaceholder({
    required double mediaWidth,
    required double maxMediaHeight,
    required double aspectRatio,
  }) {
    final normalized = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio
        : 9 / 16;
    final preferredH = mediaWidth / normalized;
    final actualH = preferredH <= maxMediaHeight ? preferredH : maxMediaHeight;
    final actualW = actualH * normalized;
    return SizedBox(
      width: actualW,
      height: actualH,
      child: const ColoredBox(color: Colors.black12),
    );
  }

  Widget _statusOverlay(String text) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.12),
        alignment: Alignment.center,
        child: _pill(text),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  double _resolveAspectRatio(ChatMedia? media, {required double fallback}) {
    final ratio = media?.aspectRatio;
    if (ratio != null && ratio.isFinite && ratio > 0) {
      return ratio;
    }
    final width = media?.width;
    final height = media?.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return fallback;
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

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 4,
            backgroundColor: Color(0xFFFF4D4F),
          ),
          SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.0,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
