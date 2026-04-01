import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:vox_flutter/application/message/media_url_resolver.dart';
import 'package:vox_flutter/models/chat_media.dart';
import 'package:vox_flutter/models/message.dart';

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
    required this.urlResolver,
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
  final Future<void> Function(String coverUrl, String videoUrl, double aspectRatio)
      onOpenDynamicPhoto;
  final MediaUrlResolver urlResolver;
  final Uint8List? localCoverBytes;
  final String? localCoverPath;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final mediaWidth = math.min(mq.size.width * 0.5, 244.0);
    final maxMediaHeight = math.min(mq.size.height * 0.34, 248.0);
    final bubble = _content(mediaWidth, maxMediaHeight);
    final status = (message.status ?? '').toUpperCase();
    final isMedia = _isMediaType(message.type);

    final avatar = _Avatar(
      name: isMine ? myName : peerName,
      avatarUrl: isMine ? myAvatarUrl : peerAvatarUrl,
      seed: message.senderId,
    );

    final column = Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        bubble,
        if (status == 'SENDING' && !isMedia)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: _InlineStatus(label: '发送中'),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: isMine
            ? [
                Flexible(child: column),
                const SizedBox(width: 8),
                avatar,
              ]
            : [
                avatar,
                const SizedBox(width: 8),
                Flexible(child: column),
              ],
      ),
    );
  }

  bool _isMediaType(String type) {
    final normalized = type.toUpperCase();
    return normalized == 'IMAGE' ||
        normalized == 'VIDEO' ||
        normalized == 'DYNAMIC_PHOTO';
  }

  Widget _content(double mediaWidth, double maxMediaHeight) {
    final type = message.type.toUpperCase();
    final media = message.media;

    if (type == 'TEXT') {
      return _TextBubble(text: message.content ?? '', isMine: isMine);
    }
    if (type == 'IMAGE') {
      return _imageBubble(mediaWidth, maxMediaHeight, media);
    }
    if (type == 'VIDEO') {
      return _videoBubble(mediaWidth, maxMediaHeight, media);
    }
    if (type == 'DYNAMIC_PHOTO') {
      return _dynamicBubble(mediaWidth, maxMediaHeight, media);
    }
    return _TextBubble(text: message.content ?? type, isMine: isMine);
  }

  Widget _imageBubble(
    double mediaWidth,
    double maxMediaHeight,
    ChatMedia? media,
  ) {
    final size = _mediaFrameSize(
      mediaWidth: mediaWidth,
      maxMediaHeight: maxMediaHeight,
      aspectRatio: _resolveAspectRatio(media, fallback: 1.0),
    );
    final url = message.resolvedCoverUrl;
    final sending = _isSending;

    return GestureDetector(
      onTap: url == null || url.trim().isEmpty
          ? null
          : () => onPreviewImage(urlResolver.resolve(url)),
      child: _MediaCard(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildMediaImage(url: url, fit: BoxFit.cover),
            if (sending)
              const Positioned(
                left: 10,
                bottom: 10,
                child: _InlineStatus(label: '发送中'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _videoBubble(
    double mediaWidth,
    double maxMediaHeight,
    ChatMedia? media,
  ) {
    final size = _mediaFrameSize(
      mediaWidth: mediaWidth,
      maxMediaHeight: maxMediaHeight,
      aspectRatio: _resolveAspectRatio(media, fallback: 16 / 9),
    );
    final coverUrl = message.resolvedCoverUrl;
    final videoUrl = message.resolvedPlayUrl;
    final processing = (media?.processingStatus ?? '').toUpperCase() == 'PROCESSING';
    final sending = _isSending;

    return GestureDetector(
      onTap: videoUrl == null || videoUrl.trim().isEmpty
          ? null
          : () => onPlayVideo(urlResolver.resolve(videoUrl)),
      child: _MediaCard(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildMediaImage(url: coverUrl, fit: BoxFit.cover),
            const _MediaShade(),
            if (_formatDuration(media?.duration) case final durationLabel?)
              Positioned(
                right: 8,
                bottom: 8,
                child: _DurationBadge(label: durationLabel),
              ),
            if (!processing && !sending)
              const Center(child: _PlayBadge()),
            if (sending)
              const Positioned(
                left: 10,
                bottom: 10,
                child: _InlineStatus(label: '发送中'),
              )
            else if (processing)
              const Positioned(
                left: 10,
                bottom: 10,
                child: _InlineStatus(label: '处理中'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dynamicBubble(
    double mediaWidth,
    double maxMediaHeight,
    ChatMedia? media,
  ) {
    final size = _mediaFrameSize(
      mediaWidth: mediaWidth,
      maxMediaHeight: maxMediaHeight,
      aspectRatio: _resolveAspectRatio(media, fallback: 3 / 4),
    );
    final coverUrl = message.resolvedCoverUrl;
    final videoUrl = message.resolvedPlayUrl;
    final processing = (media?.processingStatus ?? '').toUpperCase() == 'PROCESSING';
    final sending = _isSending;

    return GestureDetector(
      onTap: videoUrl == null || videoUrl.trim().isEmpty
          ? null
          : () {
              unawaited(
                onOpenDynamicPhoto(
                  coverUrl == null || coverUrl.trim().isEmpty
                      ? ''
                      : urlResolver.resolve(coverUrl),
                  urlResolver.resolve(videoUrl),
                  _resolveAspectRatio(media, fallback: 3 / 4),
                ),
              );
            },
      child: _MediaCard(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildMediaImage(url: coverUrl, fit: BoxFit.cover),
            const _MediaShade(),
            const Positioned(
              top: 8,
              left: 8,
              child: _LiveBadge(),
            ),
            if (sending)
              const Positioned(
                left: 10,
                bottom: 10,
                child: _InlineStatus(label: '发送中'),
              )
            else if (processing)
              const Positioned(
                left: 10,
                bottom: 10,
                child: _InlineStatus(label: '准备中'),
              ),
          ],
        ),
      ),
    );
  }

  bool get _isSending => (message.status ?? '').toUpperCase() == 'SENDING';

  Widget _buildMediaImage({
    required String? url,
    required BoxFit fit,
  }) {
    if (localCoverBytes != null) {
      return Image.memory(localCoverBytes!, fit: fit, gaplessPlayback: true);
    }
    if (localCoverPath != null && localCoverPath!.trim().isNotEmpty) {
      return Image.file(File(localCoverPath!), fit: fit, gaplessPlayback: true);
    }
    if (url == null || url.trim().isEmpty) {
      return const _NeutralPlaceholder();
    }
    return Image(
      image: CachedNetworkImageProvider(urlResolver.resolve(url)),
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => const _NeutralPlaceholder(),
    );
  }

  Size _mediaFrameSize({
    required double mediaWidth,
    required double maxMediaHeight,
    required double aspectRatio,
  }) {
    final safeRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1.0;
    var width = mediaWidth;
    var height = width / safeRatio;
    if (height > maxMediaHeight) {
      height = maxMediaHeight;
      width = height * safeRatio;
    }
    return Size(width, height);
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

  String? _formatDuration(double? durationSeconds) {
    if (durationSeconds == null || !durationSeconds.isFinite || durationSeconds <= 0) {
      return null;
    }
    final totalSeconds = durationSeconds.round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
        maxWidth: math.min(MediaQuery.of(context).size.width * 0.68, 320.0),
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
  const _Avatar({
    required this.name,
    required this.avatarUrl,
    required this.seed,
  });

  final String name;
  final String? avatarUrl;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: NetworkImage(avatarUrl!),
      );
    }
    final colors = <Color>[
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEF4444),
    ];
    return CircleAvatar(
      radius: 18,
      backgroundColor: colors[seed.abs() % colors.length],
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.characters.first,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}
class _MediaShade extends StatelessWidget {
  const _MediaShade();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Color(0x16000000),
            Color(0x55000000),
          ],
          stops: [0.45, 0.72, 1.0],
        ),
      ),
    );
  }
}

class _NeutralPlaceholder extends StatelessWidget {
  const _NeutralPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      alignment: Alignment.center,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0x33000000),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Icon(
          Icons.photo_outlined,
          color: Colors.white70,
        ),
      ),
    );
  }
}
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.36),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 30,
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.54),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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


