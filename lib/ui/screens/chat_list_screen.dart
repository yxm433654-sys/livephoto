import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/chat_screen.dart';
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
                return ListTile(
                  title: Text('用户 $peerId'),
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
}
