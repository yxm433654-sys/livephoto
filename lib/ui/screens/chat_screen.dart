import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:vox_flutter/application/message/conversation_flow.dart';
import 'package:vox_flutter/application/message/chat_media_action_handler.dart';
import 'package:vox_flutter/application/message/chat_message_subscription.dart';
import 'package:vox_flutter/application/message/media_url_resolver.dart';
import 'package:vox_flutter/application/message/message_workflow_facade.dart';
import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/state/app_state.dart';
import 'package:vox_flutter/ui/chat/chat_composer.dart';
import 'package:vox_flutter/ui/chat/local_message_factory.dart';
import 'package:vox_flutter/ui/chat/chat_media_navigator.dart';
import 'package:vox_flutter/ui/chat/dynamic_photo_adapter.dart';
import 'package:vox_flutter/ui/chat/message_list.dart';
import 'package:vox_flutter/ui/chat/message_sender.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.peerId});

  final int peerId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _textFocusNode = FocusNode();
  final GlobalKey _moreButtonKey = GlobalKey();
  final ConversationFlow _conversationCoordinator =
      const ConversationFlow();
  final ChatMessageSubscription _messageSubscription =
      const ChatMessageSubscription();
  final DynamicPhotoAdapter _dynamicPhotoAdapter = const DynamicPhotoAdapter();

  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<int, Uint8List> _localCoverBytesByMessageId = <int, Uint8List>{};
  final Map<int, String> _localCoverPathByMessageId = <int, String>{};

  ChatMediaNavigator? _chatMediaNavigator;
  MessageWorkflowFacade? _workflowFacade;
  StreamSubscription<ChatMessage>? _msgSub;

  bool _loading = true;
  bool _sending = false;
  bool _userAtBottom = true;
  bool _showEmojiPanel = false;
  int _lastMessageId = 0;
  int _tempMessageSeed = -1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _textCtrl.dispose();
    _textFocusNode.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    final current = _scrollCtrl.position.pixels;
    _userAtBottom = (max - current) <= 80.0;
  }

  Future<void> _init() async {
    final state = context.read<AppState>();
    final workflow = _workflow(state);
    final session = state.session;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '请重新登录后再试。';
      });
      return;
    }

    final conversationState = await _conversationCoordinator.initialize(
      workflow: workflow,
      currentUserId: session.userId,
      peerId: widget.peerId,
    );

    _messages
      ..clear()
      ..addAll(conversationState.messages);
    _lastMessageId = conversationState.lastMessageId;
    _error = conversationState.errorMessage;
    _subscribeToEvents(workflow, session.userId);

    if (!mounted) return;
    setState(() => _loading = false);
    _scrollToBottom(animated: false);
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      _scrollToBottom(animated: false);
    });
  }

  void _subscribeToEvents(MessageWorkflowFacade workflow, int currentUserId) {
    _msgSub?.cancel();
    _msgSub = _messageSubscription.bind(
      workflow: workflow,
      currentUserId: currentUserId,
      peerId: widget.peerId,
      currentMessages: _messages,
      isUserAtBottom: () => _userAtBottom,
      onBeforeApply: (incomingMessage, replacedTempId) {
        if (replacedTempId == null) return;
        final localBytes = _localCoverBytesByMessageId.remove(replacedTempId);
        final localPath = _localCoverPathByMessageId.remove(replacedTempId);
        if (localBytes != null) {
          _localCoverBytesByMessageId[incomingMessage.id] = localBytes;
        }
        if (localPath != null) {
          _localCoverPathByMessageId[incomingMessage.id] = localPath;
        }
      },
      onUpdate: (update) {
        if (!mounted) return;
        setState(() {
          _messages
            ..clear()
            ..addAll(update.conversationUpdate.messages);
          if (update.conversationUpdate.lastMessageId > _lastMessageId) {
            _lastMessageId = update.conversationUpdate.lastMessageId;
          }
          _dropLocalPreviewIfRemoteReady(update.incomingMessage);
        });
        if (update.conversationUpdate.shouldScrollToBottom) {
          _scrollToBottom(
            animated: update.incomingMessage.senderId != currentUserId,
          );
        }
      },
    );
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if (animated) {
        _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _toggleEmojiPanel() {
    setState(() => _showEmojiPanel = !_showEmojiPanel);
    if (_showEmojiPanel) {
      _textFocusNode.unfocus();
    } else {
      _textFocusNode.requestFocus();
    }
  }

  void _appendEmoji(String emoji) {
    final value = _textCtrl.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, emoji);
    final caret = start + emoji.length;
    _textCtrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  int _nextTempId() {
    final id = _tempMessageSeed;
    _tempMessageSeed -= 1;
    return id;
  }

  MessageWorkflowFacade _workflow(AppState state) {
    return _workflowFacade ??= MessageWorkflowFacade(
      messageEvents: state.messageEvents,
      prefetchPeer: state.prefetchUser,
      attachmentService: state.attachments,
      clearUnread: state.clearUnread,
      refreshSessions: state.refreshSessions,
      loadHistory: ({
        required int userId,
        required int peerId,
        required int page,
        required int size,
      }) {
        return state.messages.history(
          userId: userId,
          peerId: peerId,
          page: page,
          size: size,
        );
      },
      markRead: state.messages.markRead,
      sendText: ({
        required int senderId,
        required int receiverId,
        required String content,
      }) {
        return state.messages.sendText(
          senderId: senderId,
          receiverId: receiverId,
          content: content,
        );
      },
      sendImage: ({
        required int senderId,
        required int receiverId,
        required int resourceId,
      }) {
        return state.messages.sendImage(
          senderId: senderId,
          receiverId: receiverId,
          resourceId: resourceId,
        );
      },
      sendVideo: ({
        required int senderId,
        required int receiverId,
        required int videoResourceId,
        int? coverResourceId,
      }) {
        return state.messages.sendVideo(
          senderId: senderId,
          receiverId: receiverId,
          videoResourceId: videoResourceId,
          coverResourceId: coverResourceId,
        );
      },
      sendDynamicPhoto: ({
        required int senderId,
        required int receiverId,
        required int coverId,
        required int videoId,
      }) {
        return state.messages.sendDynamicPhoto(
          senderId: senderId,
          receiverId: receiverId,
          coverId: coverId,
          videoId: videoId,
        );
      },
      uploadFileFromPath: ({
        required String filePath,
        int? userId,
      }) {
        return state.attachments.uploadNormalFromPath(
          filePath: filePath,
          userId: userId,
        );
      },
      clearConversation: ({
        required int userId,
        required int peerId,
      }) {
        return state.messages.clearConversation(
          userId: userId,
          peerId: peerId,
        );
      },
    );
  }

  MessageSender _messageSender(AppState state, int senderId) {
    return MessageSender(
      workflow: _workflow(state),
      peerId: widget.peerId,
      senderId: senderId,
      localMessageFactory: LocalMessageFactory(
        senderId: senderId,
        receiverId: widget.peerId,
      ),
      nextTempId: _nextTempId,
      insertLocalMessage: _insertLocalMessage,
      replaceMessage: _replaceMessage,
      removeLocalMessage: _removeLocalMessage,
      setSending: (sending) {
        if (!mounted) return;
        setState(() {
          _sending = sending;
          if (sending) {
            _error = null;
          }
        });
      },
      showError: _showSnack,
    );
  }

  ChatMediaNavigator _mediaNavigator() {
    return _chatMediaNavigator ??= ChatMediaNavigator(context);
  }

  ChatMediaActionHandler _mediaActionHandler(
    AppState state,
    int currentUserId,
  ) {
    return ChatMediaActionHandler(
      context: context,
      workflow: _workflow(state),
      peerId: widget.peerId,
      currentUserId: currentUserId,
      dynamicPhotoAdapter: _dynamicPhotoAdapter,
      messageSender: _messageSender(state, currentUserId),
      sending: _sending,
      onConversationCleared: () {
        if (!mounted) return;
        setState(() {
          _messages.clear();
          _localCoverBytesByMessageId.clear();
          _localCoverPathByMessageId.clear();
        });
      },
      showSnack: _showSnack,
    );
  }

  void _insertLocalMessage(
    ChatMessage message, {
    Uint8List? localCoverBytes,
    String? localCoverPath,
  }) {
    setState(() {
      _messages.add(message);
      _messages.sort(_conversationCoordinator.compareMessages);
      if (localCoverBytes != null) {
        _localCoverBytesByMessageId[message.id] = localCoverBytes;
      }
      if (localCoverPath != null && localCoverPath.trim().isNotEmpty) {
        _localCoverPathByMessageId[message.id] = localCoverPath;
      }
    });
    _scrollToBottom(animated: false);
  }

  void _replaceMessage(int tempId, ChatMessage message) {
    final index = _messages.indexWhere((item) => item.id == tempId);
    if (index < 0) return;
    final localBytes = _localCoverBytesByMessageId.remove(tempId);
    final localPath = _localCoverPathByMessageId.remove(tempId);
    setState(() {
      _messages[index] = message;
      if (localBytes != null) {
        _localCoverBytesByMessageId[message.id] = localBytes;
      }
      if (localPath != null) {
        _localCoverPathByMessageId[message.id] = localPath;
      }
    });
  }

  void _removeLocalMessage(int tempId) {
    setState(() {
      _messages.removeWhere((item) => item.id == tempId);
      _localCoverBytesByMessageId.remove(tempId);
      _localCoverPathByMessageId.remove(tempId);
    });
  }

  bool _shouldShowTimestamp(int index) {
    if (index <= 0) return true;
    final current = _messages[index].createdAt;
    final previous = _messages[index - 1].createdAt;
    if (current == null || previous == null) return true;
    return current.difference(previous).abs() >= const Duration(minutes: 5);
  }

  String _formatTimestamp(DateTime? time) {
    if (time == null) return '';
    return DateFormat('HH:mm').format(time.toLocal());
  }

  void _dropLocalPreviewIfRemoteReady(ChatMessage message) {
    final hasRemoteCover = message.resolvedCoverUrl?.trim().isNotEmpty == true;
    final hasRemoteImage = message.resolvedCoverUrl?.trim().isNotEmpty == true;
    final hasRemoteVideo = message.resolvedPlayUrl?.trim().isNotEmpty == true;
    final type = message.type.toUpperCase();

    if (type == 'IMAGE' && hasRemoteImage) {
      _localCoverBytesByMessageId.remove(message.id);
      _localCoverPathByMessageId.remove(message.id);
    }
    if ((type == 'VIDEO' || type == 'DYNAMIC_PHOTO') &&
        hasRemoteCover &&
        hasRemoteVideo) {
      _localCoverBytesByMessageId.remove(message.id);
      _localCoverPathByMessageId.remove(message.id);
    }
  }

  Future<void> _sendText() async {
    if (_sending) return;
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) return;

    await _messageSender(state, session.userId).sendText(
      text: text,
      onQueued: _textCtrl.clear,
      onFailedRestore: (failedText) {
        _textCtrl.text = failedText;
      },
    );
  }

  Future<void> _showAttachMenu() async {
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) return;
    await _mediaActionHandler(state, session.userId).showAttachMenu();
  }

  Future<void> _handleChatAction(_ChatAction action) async {
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) return;
    final handler = _mediaActionHandler(state, session.userId);
    switch (action) {
      case _ChatAction.clearConversation:
        await handler.clearConversation();
        break;
      case _ChatAction.clearCache:
        await handler.clearMediaCache();
        break;
    }
  }

  Future<void> _showChatActionsSheet() async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final button = _moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || button == null) return;

    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final action = await showMenu<_ChatAction>(
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
      items: const [
        PopupMenuItem(
          value: _ChatAction.clearConversation,
          child: _MenuActionRow(
            icon: Icons.delete_sweep_outlined,
            label: '清空聊天记录',
          ),
        ),
        PopupMenuItem(
          value: _ChatAction.clearCache,
          child: _MenuActionRow(
            icon: Icons.cleaning_services_outlined,
            label: '清除媒体缓存',
          ),
        ),
      ],
    );
    if (action != null) {
      await _handleChatAction(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final session = state.session;
    final myId = session?.userId ?? 0;
    final myName = session?.username ?? 'Me';
    final peerName = state.displayNameFor(widget.peerId);
    final myAvatarUrl = session == null ? null : state.avatarUrlFor(myId);
    final peerAvatarUrl = state.avatarUrlFor(widget.peerId);
    final mediaNavigator = _mediaNavigator();
    final urlResolver = MediaUrlResolver(state.apiBaseUrl);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage:
                  peerAvatarUrl == null ? null : NetworkImage(peerAvatarUrl),
              child: peerAvatarUrl == null
                  ? Text(peerName.trim().isEmpty ? '?' : peerName.characters.first)
                  : null,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(peerName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: _moreButtonKey,
            onPressed: _showChatActionsSheet,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.connectionNotice != null && state.connectionNotice!.isNotEmpty)
            MaterialBanner(
              content: Text(state.connectionNotice!),
              actions: [
                TextButton(
                  onPressed: state.clearConnectionNotice,
                  child: const Text('知道了'),
                ),
              ],
            ),
          if (_error != null && _error!.isNotEmpty)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _loading = true;
                    });
                    _init();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          Expanded(
            child: ChatMessageList(
              loading: _loading,
              scrollController: _scrollCtrl,
              messages: _messages,
              myId: myId,
              myName: myName,
              peerName: peerName,
              myAvatarUrl: myAvatarUrl,
              peerAvatarUrl: peerAvatarUrl,
              shouldShowTimestamp: _shouldShowTimestamp,
              formatTimestamp: _formatTimestamp,
              onPlayVideo: mediaNavigator.openPlayer,
              onPreviewImage: mediaNavigator.openImagePreview,
              onOpenDynamicPhoto: mediaNavigator.openDynamicPhoto,
              localCoverBytesByMessageId: _localCoverBytesByMessageId,
              localCoverPathByMessageId: _localCoverPathByMessageId,
              urlResolver: urlResolver,
            ),
          ),
          ChatComposer(
            textController: _textCtrl,
            textFocusNode: _textFocusNode,
            sending: _sending,
            showEmojiPanel: _showEmojiPanel,
            onShowAttachMenu: _showAttachMenu,
            onToggleEmojiPanel: _toggleEmojiPanel,
            onSendText: _sendText,
            onAppendEmoji: _appendEmoji,
            onHideEmojiPanel: () => setState(() => _showEmojiPanel = false),
            emojiSet: _emojiSet,
          ),
        ],
      ),
    );
  }
}

enum _ChatAction { clearConversation, clearCache }

const List<String> _emojiSet = <String>[
  '😀','😁','😂','😅','😉','😍','😘','🤔','😎','😭','😡','😴','🥳','😇','🤗','🙌','👏','👍','✌️','🔥','🎉','❤️','💡','🌈','🍀','☕','🎧','📷','🚀','🌙','⭐','🐶','🐱','🦊','🫶',
];

class _MenuActionRow extends StatelessWidget {
  const _MenuActionRow({required this.icon, required this.label});

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




