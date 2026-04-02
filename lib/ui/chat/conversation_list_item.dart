import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ConversationListItem extends StatelessWidget {
  const ConversationListItem({
    super.key,
    required this.name,
    required this.avatarLabel,
    required this.avatarColor,
    required this.unreadCount,
    required this.onTap,
    this.avatarUrl,
    this.subtitle,
    this.updatedAt,
  });

  final String name;
  final String avatarLabel;
  final Color avatarColor;
  final int unreadCount;
  final VoidCallback onTap;
  final String? avatarUrl;
  final String? subtitle;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final resolvedSubtitle = subtitle ??
        (unreadCount > 0 ? '$unreadCount 条未读消息' : '点击进入聊天');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _ConversationAvatar(
                avatarColor: avatarColor,
                avatarLabel: avatarLabel,
                avatarUrl: avatarUrl,
                unreadCount: unreadCount,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (updatedAt != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            _formatTimestamp(updatedAt!),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      resolvedSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: unreadCount > 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF6B7280),
                        fontWeight:
                            unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year && local.month == now.month && local.day == now.day;
    if (sameDay) {
      return DateFormat('HH:mm').format(local);
    }
    return DateFormat('MM/dd').format(local);
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({
    required this.avatarColor,
    required this.avatarLabel,
    required this.avatarUrl,
    required this.unreadCount,
  });

  final Color avatarColor;
  final String avatarLabel;
  final String? avatarUrl;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatarUrl == null
            ? CircleAvatar(
                radius: 24,
                backgroundColor: avatarColor,
                child: Text(
                  avatarLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : CircleAvatar(
                radius: 24,
                backgroundImage: NetworkImage(avatarUrl!),
              ),
        if (unreadCount > 0)
          Positioned(
            top: -4,
            right: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
