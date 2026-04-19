import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vox_flutter/application/session/session_list_coordinator.dart';
import 'package:vox_flutter/application/session/session_list_facade.dart';
import 'package:vox_flutter/application/session/session_list_item_view_data.dart';
import 'package:vox_flutter/models/user.dart';
import 'package:vox_flutter/state/app_state.dart';
import 'package:vox_flutter/state/session_list_state_adapter.dart';
import 'package:vox_flutter/ui/chat/add_conversation_dialog.dart';
import 'package:vox_flutter/ui/chat/conversation_list_item.dart';
import 'package:vox_flutter/ui/screens/chat_screen.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  final GlobalKey _menuButtonKey = GlobalKey();
  final SessionListCoordinator _sessionListCoordinator =
      const SessionListCoordinator();
  final SessionListStateAdapter _sessionListStateAdapter =
      const SessionListStateAdapter();

  Future<void> _addConversation(SessionListFacade sessionList) async {
    final selectedUser = await showDialog<UserProfile>(
      context: context,
      builder: (_) => const AddConversationDialog(),
    );

    if (selectedUser == null || !mounted) return;
    await sessionList.addPeer(selectedUser.userId);
    await sessionList.prefetchUser(selectedUser.userId);
  }

  Future<bool> _confirmDelete(SessionListFacade sessionList, int peerId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除会话'),
        content: Text(
          '要把 ${sessionList.displayNameFor(peerId)} 从会话列表中移除吗？',
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
    if (trimmed.isNotEmpty) {
      return trimmed.characters.first;
    }
    return id.toString();
  }

  Future<void> _openMenu(SessionListFacade sessionList) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final button = _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 64,
          child: _ConversationMenuAccount(
            username: sessionList.currentUsername,
            userId: sessionList.currentUserId,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'add',
          child: _ConversationMenuRow(
            icon: Icons.add_comment_outlined,
            label: '添加会话',
          ),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: _ConversationMenuRow(
            icon: Icons.logout_rounded,
            label: '退出登录',
          ),
        ),
      ],
    );

    if (value == 'add') {
      await _addConversation(sessionList);
    } else if (value == 'logout') {
      await sessionList.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sessionList = _sessionListCoordinator.buildFacade(
      state: _sessionListStateAdapter.fromAppState(state),
      prefetchUser: state.prefetchUser,
      addPeer: state.addPeer,
      removePeer: state.removePeer,
      clearUnread: state.clearUnread,
      displayNameFor: state.displayNameFor,
      clearConnectionNotice: state.clearConnectionNotice,
      logout: state.logout,
    );
    final sessionItems = sessionList.items;
    final username = sessionList.currentUsername;
    final userId = sessionList.currentUserId;
    final avatarUrl = sessionList.currentAvatarUrl;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7FB),
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: avatarUrl == null
                ? CircleAvatar(
                    radius: 18,
                    backgroundColor: _avatarColor(userId),
                    child: Text(
                      _avatarText(username, userId),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(avatarUrl),
                  ),
          ),
        ),
        title: const Text(
          '会话',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            key: _menuButtonKey,
            onPressed: () => _openMenu(sessionList),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (sessionList.connectionNotice != null)
            MaterialBanner(
              content: Text(sessionList.connectionNotice!),
              actions: [
                TextButton(
                  onPressed: sessionList.clearConnectionNotice,
                  child: const Text('知道了'),
                ),
              ],
            ),
          Expanded(
            child: sessionItems.isEmpty
                ? const _EmptyConversationState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: sessionItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final SessionListItemViewData item = sessionItems[index];
                      final peerId = item.peerId;
                      sessionList.prefetchUser(peerId);

                      return Dismissible(
                        key: ValueKey('peer-$peerId'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmDelete(sessionList, peerId),
                        onDismissed: (_) => sessionList.removePeer(peerId),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                        child: ConversationListItem(
                          name: item.name,
                          avatarLabel: _avatarText(item.name, peerId),
                          avatarColor: _avatarColor(peerId),
                          avatarUrl: item.avatarUrl,
                          unreadCount: item.unreadCount,
                          subtitle: item.subtitle,
                          updatedAt: item.updatedAt,
                          onTap: () {
                            sessionList.clearUnread(peerId);
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
  const _ConversationMenuRow({required this.icon, required this.label});

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

class _ConversationMenuAccount extends StatelessWidget {
  const _ConversationMenuAccount({
    required this.username,
    required this.userId,
  });

  final String username;
  final int userId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'ID $userId',
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF6B7280),
          ),
        ),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击右上角菜单，搜索用户名后添加会话。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

