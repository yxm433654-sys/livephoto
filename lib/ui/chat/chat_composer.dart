import 'package:flutter/material.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.textController,
    required this.textFocusNode,
    required this.sending,
    required this.showEmojiPanel,
    required this.onShowAttachMenu,
    required this.onToggleEmojiPanel,
    required this.onSendText,
    required this.onAppendEmoji,
    required this.onHideEmojiPanel,
    required this.emojiSet,
  });

  final TextEditingController textController;
  final FocusNode textFocusNode;
  final bool sending;
  final bool showEmojiPanel;
  final Future<void> Function() onShowAttachMenu;
  final VoidCallback onToggleEmojiPanel;
  final Future<void> Function() onSendText;
  final void Function(String emoji) onAppendEmoji;
  final VoidCallback onHideEmojiPanel;
  final List<String> emojiSet;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ComposerIconButton(
                  icon: Icons.add_rounded,
                  onTap: sending ? null : () => onShowAttachMenu(),
                ),
                const SizedBox(width: 8),
                _ComposerIconButton(
                  icon: Icons.sentiment_satisfied_alt_rounded,
                  onTap: onToggleEmojiPanel,
                  active: showEmojiPanel,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0F111827),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: textController,
                      focusNode: textFocusNode,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onTap: () {
                        if (showEmojiPanel) {
                          onHideEmojiPanel();
                        }
                      },
                      onSubmitted: (_) => onSendText(),
                      decoration: const InputDecoration(
                        hintText: '输入消息',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: sending ? null : () => onSendText(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(52, 52),
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFF10B981),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
            if (showEmojiPanel) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: emojiSet
                      .map(
                        (emoji) => InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onAppendEmoji(emoji),
                          child: Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
const _ComposerIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE0F2FE) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? const Color(0xFF7DD3FC) : const Color(0xFFE5E7EB),
        ),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(
          icon,
          color: active ? const Color(0xFF0284C7) : const Color(0xFF374151),
        ),
      ),
    );
  }
}
