import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/chat_screen.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  Future<void> _addPeer(BuildContext context) async {
    final controller = TextEditingController();
    final peerId = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('添加会话'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '对方用户ID'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                Navigator.of(ctx).pop(v);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (peerId == null) return;
    if (!context.mounted) return;
    await context.read<AppState>().addPeer(peerId);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final session = state.session!;
    return Scaffold(
      appBar: AppBar(
        title: Text('会话 (我: ${session.userId})'),
        actions: [
          IconButton(
            onPressed: () => _addPeer(context),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            onPressed: () => state.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: state.peers.isEmpty
          ? const Center(child: Text('还没有会话，点右上角 + 添加对方用户ID'))
          : ListView.separated(
              itemCount: state.peers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final peerId = state.peers[idx];
                final unread = state.unreadByPeer[peerId] ?? 0;
                final last = state.lastMessageByPeer[peerId];
                return ListTile(
                  title: Text('用户 $peerId', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: last == null ? null : Text(_preview(last), maxLines: 1, overflow: TextOverflow.ellipsis),
                  leading: _Avatar(peerId: peerId, unread: unread),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => state.removePeer(peerId),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(peerId: peerId)),
                    );
                  },
                );
              },
            ),
    );
  }

  static String _preview(ChatMessage message) {
    final type = message.type.toUpperCase();
    if (type == 'TEXT') {
      return message.content ?? '';
    }
    if (type == 'IMAGE') return '[图片]';
    if (type == 'VIDEO') return '[视频]';
    if (type == 'DYNAMIC_PHOTO') return '[动态图片]';
    return '[$type]';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.peerId, required this.unread});

  final int peerId;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final text = peerId.toString();
    final label = text.length <= 2 ? text : text.substring(text.length - 2);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
        ),
        if (unread > 0)
          Positioned(
            right: -4,
            top: -4,
            child: _UnreadBadge(count: unread),
          ),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onError,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
