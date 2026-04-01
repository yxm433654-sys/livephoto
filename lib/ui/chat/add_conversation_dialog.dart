import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vox_flutter/models/user.dart';
import 'package:vox_flutter/state/app_state.dart';

class AddConversationDialog extends StatefulWidget {
  const AddConversationDialog({super.key});

  @override
  State<AddConversationDialog> createState() => _AddConversationDialogState();
}

class _AddConversationDialogState extends State<AddConversationDialog> {
  final TextEditingController _controller = TextEditingController();
  UserProfile? _foundUser;
  String? _error;
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final username = _controller.text.trim();
    if (username.isEmpty) {
      setState(() {
        _foundUser = null;
        _error = '请输入用户名。';
      });
      return;
    }

    final appState = context.read<AppState>();
    final session = appState.session;
    if (session != null && session.username == username) {
      setState(() {
        _foundUser = null;
        _error = '不能添加自己。';
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _foundUser = null;
    });

    final user = await appState.findUserByUsername(username);
    if (!mounted) {
      return;
    }

    setState(() {
      _searching = false;
      _foundUser = user;
      _error = user == null ? '没有找到这个用户。' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加会话'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: '搜索用户名',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: _searching ? null : _search,
                child: const Text('搜索'),
              ),
            ),
            const SizedBox(height: 16),
            if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: CircularProgressIndicator(),
              )
            else if (_foundUser != null)
              _FoundUserCard(user: _foundUser!)
            else if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    height: 1.45,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed:
              _foundUser == null ? null : () => Navigator.of(context).pop(_foundUser),
          child: const Text('添加会话'),
        ),
      ],
    );
  }
}

class _FoundUserCard extends StatelessWidget {
  const _FoundUserCard({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage:
                user.avatarUrl == null || user.avatarUrl!.isEmpty
                    ? null
                    : NetworkImage(user.avatarUrl!),
            child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                ? Text(user.username.characters.first)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.username,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '用户 ID: ${user.userId}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
