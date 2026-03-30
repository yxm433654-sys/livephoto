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
    final mediaWidth = math.min(MediaQuery.of(context).size.width * 0.5, 240.0);
    final maxMediaHeight =
        math.min(MediaQuery.of(context).size.height * 0.36, 260.0);
    final bubble = _buildContent(context, mediaWidth, maxMediaHeight);
    final time = message.createdAt == null
        ? ''
        : DateFormat('HH:mm').format(message.createdAt!.toLocal());

    final avatar = _Avatar(
      name: isMine ? myName : peerName,
      avatarUrl: isMine ? myAvatarUrl : peerAvatarUrl,
      seed: message.senderId,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: isMine
            ? [
                Text(
                  time,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
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
                Text(
                  time,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    double mediaWidth,
    double maxMediaHeight,
  ) {
    final type = message.type.toUpperCase();
    final media = message.media;

    if (type == 'TEXT') {
      return _TextBubble(text: message.content ?? '', isMine: isMine);
    }

    if (type == 'IMAGE') {
      return _buildImageBubble(context, mediaWidth, maxMediaHeight, media);
    }

    if (type == 'VIDEO') {
      return _buildVideoBubble(context, mediaWidth, maxMediaHeight, media);
    }

    if (type == 'DYNAMIC_PHOTO') {
      return _buildDynamicBubble(context, mediaWidth, maxMediaHeight, media);
    }

    return _TextBubble(text: message.content ?? type, isMine: isMine);
  }

  Widget _buildImageBubble(
    BuildContext context,
    double mediaWidth,
    double maxMediaHeight,
    ChatMedia? media,
  ) {
    final aspectRatio = _resolveAspectRatio(media, fallback: 1.0);
    final size = _mediaFrameSize(
      mediaWidth: mediaWidth,
      maxMediaHeight: maxMediaHeight,
      aspectRatio: aspectRatio,
    );
    final imageUrl = media?.coverUrl ?? message.coverUrl;

    return GestureDetector(
      onTap: imageUrl == null || imageUrl.trim().isEmpty
          ? null
          : () => onPreviewImage(_resolveUrl(context, imageUrl)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: _mediaSurface(
            child: _buildPreviewImage(
              context: context,
              url: imageUrl,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoBubble(
    BuildContext context,
    double mediaWidth,
    double maxMediaHeight,
    ChatMedia? media,
  ) {
    final aspectRatio = _resolveAspectRatio(media, fallback: 16 / 9);
    final size = _mediaFrameSize(
      mediaWidth: mediaWidth,
      maxMediaHeight: maxMediaHeight,
      aspectRatio: aspectRatio,
    );
    final videoUrl = media?.playUrl ?? message.videoUrl;

    return GestureDetector(
      onTap: videoUrl == null || videoUrl.trim().isEmpty
          ? null
          : () => onPlayVideo(_resolveUrl(context, videoUrl)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _mediaSurface(
                child: _buildPreviewImage(
                  context: context,
                  url: media?.coverUrl ?? message.coverUrl,
                  fit: BoxFit.cover,
                ),
              ),
              _buildDarkOverlay(),
              const Center(child: _PlayButton()),
              if ((media?.processingStatus ?? '').toUpperCase() == 'PROCESSING')
                const Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: _StatusPill(text: 'Processing'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicBubble(
    BuildContext context,
    double mediaWidth,
    double maxMediaHeight,
    ChatMedia? media,
  ) {
    final aspectRatio = _resolveAspectRatio(media, fallback: 3 / 4);
    final size = _mediaFrameSize(
      mediaWidth: mediaWidth,
      maxMediaHeight: maxMediaHeight,
      aspectRatio: aspectRatio,
    );
    final coverUrl = media?.coverUrl ?? message.coverUrl;
    final videoUrl = media?.playUrl ?? message.videoUrl;

    return GestureDetector(
      onTap: videoUrl == null || videoUrl.trim().isEmpty
          ? null
          : () => onOpenDynamicPhoto(
                coverUrl == null || coverUrl.trim().isEmpty
                    ? ''
                    : _resolveUrl(context, coverUrl),
                _resolveUrl(context, videoUrl),
              ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _mediaSurface(
                child: _buildPreviewImage(
                  context: context,
                  url: coverUrl,
                  fit: BoxFit.cover,
                ),
              ),
              _buildDarkOverlay(),
              const Positioned(
                left: 10,
                top: 10,
                child: _LiveBadge(),
              ),
              if ((media?.processingStatus ?? '').toUpperCase() == 'PROCESSING')
                const Center(
                  child: _StatusPill(text: 'Preparing'),
                )
              else
                const Center(child: _PlayButton()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewImage({
    required BuildContext context,
    required String? url,
    required BoxFit fit,
  }) {
    if (localCoverBytes != null) {
      return Image.memory(localCoverBytes!, fit: fit);
    }
    if (localCoverPath != null && localCoverPath!.trim().isNotEmpty) {
      return Image.file(File(localCoverPath!), fit: fit);
    }
    if (url == null || url.trim().isEmpty) {
      return const _PlaceholderArtwork();
    }
    return CachedNetworkImage(
      imageUrl: _resolveUrl(context, url),
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 140),
      fadeOutDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => const _PlaceholderArtwork(),
      errorWidget: (_, __, ___) => const _PlaceholderArtwork(),
    );
  }

  Widget _mediaSurface({required Widget child}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1F2937),
            Color(0xFF111827),
          ],
        ),
      ),
      child: child,
    );
  }

  Widget _buildDarkOverlay() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.08),
            Colors.black.withOpacity(0.28),
          ],
        ),
      ),
    );
  }

  Size _mediaFrameSize({
    required double mediaWidth,
    required double maxMediaHeight,
    required double aspectRatio,
  }) {
    final safeRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1;
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
  const _Avatar({
    required this.name,
    required this.avatarUrl,
    required this.seed,
  });

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
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first;
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
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PlaceholderArtwork extends StatelessWidget {
  const _PlaceholderArtwork();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
            Color(0xFF1D4ED8),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.image_outlined,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.34),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.play_arrow,
        color: Colors.white,
        size: 30,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.44),
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
