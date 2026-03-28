import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.onPlayVideo,
  });

  final ChatMessage message;
  final bool isMine;
  final void Function(String url) onPlayVideo;

  @override
  Widget build(BuildContext context) {
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isMine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    final fg = isMine
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSecondaryContainer;

    final time = message.createdAt == null
        ? ''
        : DateFormat('HH:mm:ss').format(message.createdAt!.toLocal());

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Card(
          color: bg,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: DefaultTextStyle(
              style: TextStyle(color: fg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _content(context),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(time,
                          style: TextStyle(
                              color: fg.withOpacity(0.7), fontSize: 11)),
                      if (!isMine) ...[
                        const SizedBox(width: 8),
                        Text(message.status ?? '',
                            style: TextStyle(
                                color: fg.withOpacity(0.7), fontSize: 11)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final t = message.type.toUpperCase();
    if (t == 'TEXT') {
      return Text(message.content ?? '');
    }

    if (t == 'IMAGE') {
      final url = message.coverUrl;
      if (url == null || url.isEmpty) return const Text('图片不可用');
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url, fit: BoxFit.cover),
      );
    }

    if (t == 'VIDEO') {
      final url = message.videoUrl ?? message.coverUrl;
      if (url == null || url.isEmpty) return const Text('视频不可用');
      return _videoPreview(url);
    }

    if (t == 'DYNAMIC_PHOTO') {
      final cover = message.coverUrl;
      final video = message.videoUrl;
      if (cover == null || cover.isEmpty || video == null || video.isEmpty) {
        return const Text('动态图片不可用');
      }
      return Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(cover, fit: BoxFit.cover),
          ),
          IconButton.filledTonal(
            onPressed: () => onPlayVideo(video),
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      );
    }

    return Text(message.content ?? t);
  }

  Widget _videoPreview(String url) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.black12,
          ),
          child: const Center(child: Icon(Icons.videocam_outlined)),
        ),
        IconButton.filledTonal(
          onPressed: () => onPlayVideo(url),
          icon: const Icon(Icons.play_arrow),
        ),
      ],
    );
  }
}
