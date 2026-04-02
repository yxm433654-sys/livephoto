import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:vox_flutter/application/message/chat_media_action_handler.dart';
import 'package:vox_flutter/application/message/chat_message_subscription.dart';
import 'package:vox_flutter/application/message/conversation_flow.dart';
import 'package:vox_flutter/application/message/media_url_resolver.dart';
import 'package:vox_flutter/application/message/message_workflow_facade.dart';
import 'package:vox_flutter/models/message.dart';
import 'package:vox_flutter/state/app_state.dart';
import 'package:vox_flutter/ui/chat/chat_composer.dart';
import 'package:vox_flutter/ui/chat/chat_media_navigator.dart';
import 'package:vox_flutter/ui/chat/dynamic_photo_adapter.dart';
import 'package:vox_flutter/ui/chat/local_message_factory.dart';
import 'package:vox_flutter/ui/chat/message_list.dart';
import 'package:vox_flutter/ui/chat/message_sender.dart';
import 'package:vox_flutter/utils/hidden_message_store.dart';
import 'package:vox_flutter/utils/message_attachment_actions.dart';
import 'package:vox_flutter/utils/user_error_message.dart';

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
  final ConversationFlow _conversationFlow = const ConversationFlow();
  final ChatMessageSubscription _messageSubscription =
      const ChatMessageSubscription();
  final DynamicPhotoAdapter _dynamicPhotoAdapter =
      const DynamicPhotoAdapter();

  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<int, Uint8List> _localCoverBytesByMessageId = <int, Uint8List>{};
  final Map<int, String> _localCoverPathByMessageId = <int, String>{};
  final Set<int> _hiddenMessageIds = <int>{};

  ChatMediaNavigator? _chatMediaNavigator;
  MessageWorkflowFacade? _workflowFacade;
  StreamSubscription<ChatMessage>? _messageEventSubscription;
  Timer? _processingRefreshTimer;

  bool _loading = true;
  bool _userAtBottom = true;
  bool _showEmojiPanel = false;
  bool _loadingMoreHistory = false;
  int _lastMessageId = 0;
  int _currentPage = 0;
  bool _hasMoreHistory = true;
  int _tempMessageSeed = -1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _textFocusNode.addListener(_onTextFocusChanged);
    unawaited(_init());
  }

  @override
  void dispose() {
    _messageEventSubscription?.cancel();
    _processingRefreshTimer?.cancel();
    _textCtrl.dispose();
    _textFocusNode.removeListener(_onTextFocusChanged);
    _textFocusNode.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) {
      return;
    }
    final max = _scrollCtrl.position.maxScrollExtent;
    final current = _scrollCtrl.position.pixels;
    _userAtBottom = (max - current) <= 80.0;
    if (current <= 120 && !_loadingMoreHistory && _hasMoreHistory) {
      unawaited(_loadMoreHistory());
    }
  }

  void _onTextFocusChanged() {
    if (!_textFocusNode.hasFocus) {
      return;
    }
    _userAtBottom = true;
    _scrollToBottomSettled();
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || !_textFocusNode.hasFocus) {
        return;
      }
      _scrollToBottomSettled();
    });
  }

  Future<void> _dismissComposerOverlays() async {
    if (_showEmojiPanel && mounted) {
      setState(() => _showEmojiPanel = false);
    }
    _textFocusNode.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 140));
  }

  Future<void> _init() async {
    final state = context.read<AppState>();
    final workflow = _workflow(state);
    final session = state.session;
    if (session == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Please sign in again and try later.';
      });
      return;
    }

    final hiddenIds = await HiddenMessageStore.load(
      currentUserId: session.userId,
      peerId: widget.peerId,
    );

    final conversationState = await _conversationFlow.initialize(
      workflow: workflow,
      currentUserId: session.userId,
      peerId: widget.peerId,
    );

    _hiddenMessageIds
      ..clear()
      ..addAll(hiddenIds);
    _messages
      ..clear()
      ..addAll(_filterHiddenMessages(conversationState.messages));
    _lastMessageId = conversationState.lastMessageId;
    _currentPage = conversationState.currentPage;
    _hasMoreHistory = conversationState.hasMore;
    _error = conversationState.errorMessage;
    _subscribeToEvents(workflow, session.userId);
    _syncProcessingRefreshTimer();

    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    _scrollToBottomSettled();
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) {
        return;
      }
      _scrollToBottomSettled();
    });
  }

  Future<void> _loadMoreHistory() async {
    if (_loadingMoreHistory || !_hasMoreHistory) {
      return;
    }

    final state = context.read<AppState>();
    final session = state.session;
    if (session == null || !_scrollCtrl.hasClients) {
      return;
    }

    _loadingMoreHistory = true;
    final previousOffset = _scrollCtrl.offset;
    final previousMaxExtent = _scrollCtrl.position.maxScrollExtent;

    try {
      final nextState = await _conversationFlow.loadNextPage(
        workflow: _workflow(state),
        currentUserId: session.userId,
        peerId: widget.peerId,
        currentMessages: _messages,
        currentPage: _currentPage,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _messages
          ..clear()
          ..addAll(_filterHiddenMessages(nextState.messages));
        _currentPage = nextState.currentPage;
        _hasMoreHistory = nextState.hasMore;
      });
      _syncProcessingRefreshTimer();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) {
          return;
        }
        final newMaxExtent = _scrollCtrl.position.maxScrollExtent;
        final delta = newMaxExtent - previousMaxExtent;
        final target = previousOffset + (delta > 0 ? delta : 0);
        _scrollCtrl.jumpTo(
          target.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        );
      });
    } catch (error) {
      _showSnack(UserErrorMessage.from(error));
    } finally {
      _loadingMoreHistory = false;
    }
  }

  void _subscribeToEvents(MessageWorkflowFacade workflow, int currentUserId) {
    _messageEventSubscription?.cancel();
    _messageEventSubscription = _messageSubscription.bind(
      workflow: workflow,
      currentUserId: currentUserId,
      peerId: widget.peerId,
      currentMessages: _messages,
      isUserAtBottom: () => _userAtBottom,
      onBeforeApply: (incomingMessage, replacedTempId) {
        if (replacedTempId == null) {
          return;
        }
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
        if (!mounted) {
          return;
        }
        setState(() {
          _messages
            ..clear()
            ..addAll(_filterHiddenMessages(update.conversationUpdate.messages));
          if (update.conversationUpdate.lastMessageId > _lastMessageId) {
            _lastMessageId = update.conversationUpdate.lastMessageId;
          }
          _dropLocalPreviewIfRemoteReady(update.incomingMessage);
        });
        _syncProcessingRefreshTimer();
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
      if (!mounted || !_scrollCtrl.hasClients) {
        return;
      }
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

  void _scrollToBottomSettled() {
    _scrollToBottom(animated: false);
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (!mounted) {
        return;
      }
      _scrollToBottom(animated: false);
    });
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
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
      attachmentService: state.attachments,
      prefetchPeer: state.prefetchUser,
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
      sendFile: ({
        required int senderId,
        required int receiverId,
        required int resourceId,
        required String fileName,
      }) {
        return state.messages.sendFile(
          senderId: senderId,
          receiverId: receiverId,
          resourceId: resourceId,
          fileName: fileName,
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
      getMessageById: _messageById,
      getLocalPathByMessageId: _localPathByMessageId,
      setSending: (sending) {
        if (!mounted) {
          return;
        }
        setState(() {
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
      onConversationCleared: () {
        if (!mounted) {
          return;
        }
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
      _messages.sort(_conversationFlow.compareMessages);
      if (localCoverBytes != null) {
        _localCoverBytesByMessageId[message.id] = localCoverBytes;
      }
      if (localCoverPath != null && localCoverPath.trim().isNotEmpty) {
        _localCoverPathByMessageId[message.id] = localCoverPath;
      }
    });
    _syncProcessingRefreshTimer();
    _scrollToBottomSettled();
  }

  void _replaceMessage(int tempId, ChatMessage message) {
    final index = _messages.indexWhere((item) => item.id == tempId);
    if (index < 0) {
      return;
    }
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
    _syncProcessingRefreshTimer();
  }

  void _removeLocalMessage(int tempId) {
    setState(() {
      _messages.removeWhere((item) => item.id == tempId);
      _localCoverBytesByMessageId.remove(tempId);
      _localCoverPathByMessageId.remove(tempId);
    });
    _syncProcessingRefreshTimer();
  }

  ChatMessage? _messageById(int id) {
    for (final message in _messages) {
      if (message.id == id) {
        return message;
      }
    }
    return null;
  }

  String? _localPathByMessageId(int id) {
    return _localCoverPathByMessageId[id];
  }


  List<ChatMessage> _filterHiddenMessages(List<ChatMessage> messages) {
    if (_hiddenMessageIds.isEmpty) {
      return List<ChatMessage>.from(messages);
    }
    return messages.where((message) => !_hiddenMessageIds.contains(message.id)).toList();
  }

  bool _needsProcessingRefresh(ChatMessage message) {
    final type = message.type.toUpperCase();
    if (type != 'VIDEO' && type != 'DYNAMIC_PHOTO') {
      return false;
    }
    return (message.media?.processingStatus ?? '').toUpperCase() == 'PROCESSING';
  }

  void _syncProcessingRefreshTimer() {
    final needsRefresh = _messages.any(_needsProcessingRefresh);
    if (!needsRefresh) {
      _processingRefreshTimer?.cancel();
      _processingRefreshTimer = null;
      return;
    }
    _processingRefreshTimer ??= Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshProcessingMessages()),
    );
  }

  Future<void> _refreshProcessingMessages() async {
    if (!mounted || _messages.isEmpty) {
      return;
    }
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) {
      return;
    }

    try {
      final latestMessages = await _workflow(state).loadHistory(
        userId: session.userId,
        peerId: widget.peerId,
        page: 0,
        size: ConversationFlow.initialPageSize,
      );
      if (!mounted) {
        return;
      }

      final latestById = <int, ChatMessage>{
        for (final item in latestMessages) item.id: item,
      };
      var changed = false;
      setState(() {
        for (var i = 0; i < _messages.length; i += 1) {
          final current = _messages[i];
          final updated = latestById[current.id];
          if (updated == null) {
            continue;
          }
          if (!_isMessageRefreshChanged(current, updated)) {
            continue;
          }
          _messages[i] = updated;
          _dropLocalPreviewIfRemoteReady(updated);
          changed = true;
        }
      });
      if (changed || !_messages.any(_needsProcessingRefresh)) {
        _syncProcessingRefreshTimer();
      }
    } catch (_) {}
  }

  bool _isMessageRefreshChanged(ChatMessage current, ChatMessage updated) {
    return current.status != updated.status ||
        current.coverUrl != updated.coverUrl ||
        current.videoUrl != updated.videoUrl ||
        current.resourceId != updated.resourceId ||
        current.videoResourceId != updated.videoResourceId ||
        current.media?.processingStatus != updated.media?.processingStatus ||
        current.media?.coverUrl != updated.media?.coverUrl ||
        current.media?.playUrl != updated.media?.playUrl ||
        current.media?.sourceType != updated.media?.sourceType;
  }


  Future<void> _openFileMessage(ChatMessage message) async {
    try {
      await MessageAttachmentActions.openFileMessage(
        message: message,
        urlResolver: MediaUrlResolver(context.read<AppState>().apiBaseUrl),
      );
    } catch (error) {
      _showSnack(UserErrorMessage.from(error));
    }
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final session = context.read<AppState>().session;
    if (session == null) {
      return;
    }

    final canSave = const <String>{'IMAGE', 'VIDEO', 'DYNAMIC_PHOTO', 'FILE'}
        .contains(message.type.toUpperCase());
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canSave)
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('Save to device'),
                  onTap: () => Navigator.of(sheetContext).pop(_MessageAction.saveLocal),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete'),
                subtitle: const Text('Hide on this device only. This does not affect the other user or the server history.'),
                onTap: () => Navigator.of(sheetContext).pop(_MessageAction.deleteLocal),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    switch (action) {
      case _MessageAction.saveLocal:
        await _saveMessageLocally(message);
        break;
      case _MessageAction.deleteLocal:
        await _deleteMessageLocally(session.userId, message);
        break;
      case null:
        break;
    }
  }

  Future<void> _saveMessageLocally(ChatMessage message) async {
    try {
      final notice = await MessageAttachmentActions.saveToLocal(
        message: message,
        urlResolver: MediaUrlResolver(context.read<AppState>().apiBaseUrl),
      );
      _showSnack(notice);
    } catch (error) {
      _showSnack(UserErrorMessage.from(error));
    }
  }

  Future<void> _deleteMessageLocally(int currentUserId, ChatMessage message) async {
    await HiddenMessageStore.hide(
      currentUserId: currentUserId,
      peerId: widget.peerId,
      messageId: message.id,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _hiddenMessageIds.add(message.id);
      _messages.removeWhere((item) => item.id == message.id);
      _localCoverBytesByMessageId.remove(message.id);
      _localCoverPathByMessageId.remove(message.id);
    });
    _syncProcessingRefreshTimer();
    _showSnack('Hidden on this device only. This does not affect the other user or the server history.');
  }

  Future<void> _retryMessage(ChatMessage message) async {
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) {
      _showSnack('Please sign in again and try later.');
      return;
    }
    await _messageSender(state, session.userId).retryMessage(message);
  }

  bool _shouldShowTimestamp(int index) {
    if (index <= 0) {
      return true;
    }
    final current = _messages[index].createdAt;
    final previous = _messages[index - 1].createdAt;
    if (current == null || previous == null) {
      return true;
    }
    return current.difference(previous).abs() >= const Duration(minutes: 5);
  }

  String _formatTimestamp(DateTime? time) {
    if (time == null) {
      return '';
    }
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
    _userAtBottom = true;
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      return;
    }

    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) {
      return;
    }

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
    if (session == null) {
      return;
    }

    _userAtBottom = true;
    await _dismissComposerOverlays();
    if (!mounted) {
      return;
    }
    await _mediaActionHandler(state, session.userId).showAttachMenu();
  }

  Future<void> _handleChatAction(_ChatAction action) async {
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) {
      return;
    }
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
    if (overlay == null || button == null) {
      return;
    }

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
            label: 'Clear conversation',
          ),
        ),
        PopupMenuItem(
          value: _ChatAction.clearCache,
          child: _MenuActionRow(
            icon: Icons.cleaning_services_outlined,
            label: 'Clear media cache',
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
                  child: const Text('Dismiss'),
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
                    unawaited(_init());
                  },
                  child: const Text('Retry'),
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
              onRetryMessage: _retryMessage,
              onOpenFileMessage: _openFileMessage,
              onShowMessageActions: _showMessageActions,
            ),
          ),
          ChatComposer(
            textController: _textCtrl,
            textFocusNode: _textFocusNode,
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
enum _MessageAction { saveLocal, deleteLocal }

const List<String> _emojiSet = <String>[
  '😀',
  '😁',
  '😂',
  '😅',
  '😉',
  '😍',
  '😘',
  '🤔',
  '😎',
  '😭',
  '😡',
  '😴',
  '🥳',
  '😇',
  '🤗',
  '🙌',
  '👏',
  '👍',
  '✌️',
  '🔥',
  '🎉',
  '❤️',
  '💡',
  '🌈',
  '🍀',
  '☕',
  '🎧',
  '📷',
  '🚀',
  '🌙',
  '⭐',
  '🐶',
  '🐱',
  '🦊',
  '🫶',
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
