import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/ui/chat/add_conversation_dialog.dart';
import 'package:dynamic_photo_chat_flutter/ui/chat/conversation_list_item.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final GlobalKey _menuButtonKey = GlobalKey();

  Future<void> _addConversation() async {
    final selectedUser = await showDialog(
      context: context,
      builder: (_) => const AddConversationDialog(),
    );

    if (selectedUser == null || !mounted) return;
    final appState = context.read<AppState>();
    await appState.addPeer(selectedUser.userId);
    await appState.prefetchUser(selectedUser.userId);
  }

  Future<bool> _confirmDelete(BuildContext context, int peerId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除会话'),
        content: Text(
          '要把 ${context.read<AppState>().displayNameFor(peerId)} 从会话列表中移除吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Color _avatarColor(int id) {
    final colors = <Color>[
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEF4444),
    ];
    return colors[id.abs() % colors.length];
  }

  String _avatarText(String name, int id) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed.characters.first;
    return id.toString();
  }

  Future<void> _openMenu(AppState state) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final button =
        _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || button == null) return;

    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy + 8,
        overlay.size.width - bottomRight.dx,
        overlay.size.height - topLeft.dy,
      ),
      color: Colors.white,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'add',
          child: _ConversationMenuRow(
            icon: Icons.add_comment_outlined,
            label: '添加会话',
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: _ConversationMenuRow(
            icon: Icons.logout_rounded,
            label: '退出登录',
          ),
        ),
      ],
    );

    if (value == 'add') {
      await _addConversation();
    } else if (value == 'logout') {
      await state.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final session = state.session;
    final username = session?.username ?? '游客';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7FB),
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              username,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              '会话',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: _menuButtonKey,
            onPressed: () => _openMenu(state),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.connectionNotice != null)
            MaterialBanner(
              content: Text(state.connectionNotice!),
              actions: [
                TextButton(
                  onPressed: state.clearConnectionNotice,
                  child: const Text('知道了'),
                ),
              ],
            ),
          Expanded(
            child: state.peers.isEmpty
                ? const _EmptyConversationState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: state.peers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final peerId = state.peers[index];
                      state.prefetchUser(peerId);
                      final unread = state.unreadCount(peerId);
                      final name = state.displayNameFor(peerId);
                      final avatarUrl = state.avatarUrlFor(peerId);

                      return Dismissible(
                        key: ValueKey('peer-$peerId'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmDelete(context, peerId),
                        onDismissed: (_) => state.removePeer(peerId),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                        child: ConversationListItem(
                          name: name,
                          avatarLabel: _avatarText(name, peerId),
                          avatarColor: _avatarColor(peerId),
                          avatarUrl: avatarUrl,
                          unreadCount: unread,
                          onTap: () {
                            state.clearUnread(peerId);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(peerId: peerId),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationMenuRow extends StatelessWidget {
  const _ConversationMenuRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF111827)),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _EmptyConversationState extends StatelessWidget {
  const _EmptyConversationState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 38,
                color: Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '还没有会话',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击右上角三个点，搜索用户名后添加会话。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
