import 'dart:async';
import 'dart:typed_data';
import 'package:dynamic_photo_chat_flutter/models/file_upload_response.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/services/dynamic_media_detector.dart';
import 'package:dynamic_photo_chat_flutter/services/dynamic_media_upload_service.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/ui/chat/chat_composer.dart';
import 'package:dynamic_photo_chat_flutter/ui/chat/chat_local_message_factory.dart';
import 'package:dynamic_photo_chat_flutter/ui/chat/chat_message_list.dart';
import 'package:dynamic_photo_chat_flutter/ui/chat/chat_media_navigator.dart';
import 'package:dynamic_photo_chat_flutter/ui/chat/chat_media_picker.dart';
import 'package:dynamic_photo_chat_flutter/ui/chat/chat_media_sender.dart';
import 'package:dynamic_photo_chat_flutter/utils/media_downloader.dart';
import 'package:dynamic_photo_chat_flutter/utils/user_error_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

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

  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<int, Uint8List> _localCoverBytesByMessageId = <int, Uint8List>{};
  final Map<int, String> _localCoverPathByMessageId = <int, String>{};
  ChatMediaNavigator? _chatMediaNavigator;
  final DynamicMediaDetector _dynamicMediaDetector = const DynamicMediaDetector();

  StreamSubscription<ChatMessage>? _msgSub;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int _lastMessageId = 0;
  bool _userAtBottom = true;
  int _tempMessageSeed = -1;
  bool _showEmojiPanel = false;

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
    final cur = _scrollCtrl.position.pixels;
    _userAtBottom = (max - cur) <= 80.0;
  }

  Future<void> _init() async {
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '请重新登录';
      });
      return;
    }

    try {
      state.prefetchUser(widget.peerId);
      final history = await state.messages.history(
        userId: session.userId,
        peerId: widget.peerId,
        page: 0,
        size: 100,
      );
      history.sort(_compareMessages);

      _messages
        ..clear()
        ..sort(_compareMessages)
        ..addAll(history);
      _lastMessageId = _messages.isEmpty
          ? 0
          : _messages.map((e) => e.id).reduce((a, b) => a > b ? a : b);

      await _markAllRead(session.userId);
      state.clearUnread(widget.peerId);
      _subscribeToEvents(state, session.userId);
    } catch (e) {
      _error = _toUserError(e);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom(animated: false);
      }
    }
  }

  void _subscribeToEvents(AppState state, int myId) {
    _msgSub?.cancel();
    _msgSub = state.messageEvents.listen((message) async {
      if (!mounted) return;
      if (!_isInThisChat(message, myId)) return;

      if (message.id > _lastMessageId) {
        _lastMessageId = message.id;
      }

      final idx = _messages.indexWhere((e) => e.id == message.id);
      final pendingIdx = idx < 0 ? _findPendingLocalIndex(message, myId) : -1;
      setState(() {
        if (idx >= 0) {
          _messages[idx] = message;
        } else if (pendingIdx >= 0) {
          final pendingId = _messages[pendingIdx].id;
          _messages[pendingIdx] = message;
          final localBytes = _localCoverBytesByMessageId.remove(pendingId);
          final localPath = _localCoverPathByMessageId.remove(pendingId);
          if (localBytes != null) {
            _localCoverBytesByMessageId[message.id] = localBytes;
          }
          if (localPath != null) {
            _localCoverPathByMessageId[message.id] = localPath;
          }
        } else {
          _messages.add(message);
        }
        _messages.sort(_compareMessages);
        _dropLocalPreviewIfRemoteReady(message);
      });

      if (message.receiverId == myId) {
        await _markMessageRead(message, myId);
        state.clearUnread(widget.peerId);
      }

      if (_userAtBottom || message.senderId == myId) {
        _scrollToBottom();
      }
    });
  }

  int _findPendingLocalIndex(ChatMessage message, int myId) {
    if (message.senderId != myId) return -1;
    return _messages.indexWhere(
      (candidate) =>
          candidate.id < 0 &&
          candidate.senderId == myId &&
          candidate.receiverId == widget.peerId &&
          candidate.type == message.type &&
          (candidate.status ?? '').toUpperCase() == 'SENDING',
    );
  }

  bool _isInThisChat(ChatMessage message, int myId) {
    final fromPeer =
        message.senderId == widget.peerId && message.receiverId == myId;
    final fromMe =
        message.senderId == myId && message.receiverId == widget.peerId;
    return fromPeer || fromMe;
  }

  Future<void> _markAllRead(int myId) async {
    for (final message in _messages) {
      await _markMessageRead(message, myId);
    }
  }

  Future<void> _markMessageRead(ChatMessage message, int myId) async {
    if (message.receiverId != myId) return;
    if ((message.status ?? '').toUpperCase() == 'READ') return;
    try {
      await context.read<AppState>().messages.markRead(message.id);
    } catch (_) {}
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

  String _toUserError(Object error) {
    return UserErrorMessage.from(error);
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

  ChatMediaSender _mediaSender(AppState state, int senderId) {
    return ChatMediaSender(
      appState: state,
      peerId: widget.peerId,
      senderId: senderId,
      localMessageFactory: ChatLocalMessageFactory(
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

  void _insertLocalMessage(
    ChatMessage message, {
    Uint8List? localCoverBytes,
    String? localCoverPath,
  }) {
    setState(() {
      _messages.add(message);
      _messages.sort(_compareMessages);
      if (localCoverBytes != null) {
        _localCoverBytesByMessageId[message.id] = localCoverBytes;
      }
      if (localCoverPath != null && localCoverPath.trim().isNotEmpty) {
        _localCoverPathByMessageId[message.id] = localCoverPath;
      }
    });
    _scrollToBottom();
  }

  void _replaceMessage(int tempId, ChatMessage message) {
    final idx = _messages.indexWhere((e) => e.id == tempId);
    if (idx < 0) return;
    final localBytes = _localCoverBytesByMessageId.remove(tempId);
    final localPath = _localCoverPathByMessageId.remove(tempId);
    setState(() {
      _messages[idx] = message;
      _messages.sort(_compareMessages);
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
      _messages.removeWhere((e) => e.id == tempId);
      _localCoverBytesByMessageId.remove(tempId);
      _localCoverPathByMessageId.remove(tempId);
    });
  }

  int _compareMessages(ChatMessage a, ChatMessage b) {
    final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
    if (aTime != bTime) {
      return aTime.compareTo(bTime);
    }
    final aTemp = a.id < 0;
    final bTemp = b.id < 0;
    if (aTemp != bTemp) {
      return aTemp ? 1 : -1;
    }
    return a.id.compareTo(b.id);
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
    if ((type == 'VIDEO' || type == 'DYNAMIC_PHOTO') && hasRemoteCover && hasRemoteVideo) {
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

    final tempId = _nextTempId();
    final tempMessage = ChatLocalMessageFactory(
      senderId: session.userId,
      receiverId: widget.peerId,
    ).build(
      id: tempId,
      type: 'TEXT',
      content: text,
      status: 'SENDING',
    );

    _textCtrl.clear();
    _insertLocalMessage(tempMessage);

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final messageId = await state.messages.sendText(
        senderId: session.userId,
        receiverId: widget.peerId,
        content: text,
      );
      final localMessageFactory = ChatLocalMessageFactory(
        senderId: session.userId,
        receiverId: widget.peerId,
      );
      _replaceMessage(
        tempId,
        localMessageFactory.build(
          id: messageId,
          type: 'TEXT',
          content: text,
          status: 'SENT',
        ),
      );
    } catch (e) {
      _removeLocalMessage(tempId);
      _textCtrl.text = text;
      _showSnack(_toUserError(e));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendImageFromPath({
    required String filePath,
    Uint8List? previewBytes,
  }) async {
    final state = context.read<AppState>();
    final session = state.session;
    if (_sending || session == null) return;
    await _mediaSender(state, session.userId).sendImageFromPath(
      filePath: filePath,
      previewBytes: previewBytes,
    );
  }

  Future<void> _sendVideoFromPath({
    required String filePath,
    Uint8List? previewBytes,
  }) async {
    final state = context.read<AppState>();
    final session = state.session;
    if (_sending || session == null) return;
    await _mediaSender(state, session.userId).sendVideoFromPath(
      filePath: filePath,
      previewBytes: previewBytes,
    );
  }

  Future<void> _sendDynamicPhoto({
    required String coverPath,
    Uint8List? previewBytes,
    required Future<FileUploadResponse> Function(int userId) upload,
  }) async {
    final state = context.read<AppState>();
    final session = state.session;
    if (_sending || session == null) return;
    await _mediaSender(state, session.userId).sendDynamicPhoto(
      coverPath: coverPath,
      previewBytes: previewBytes,
      upload: upload,
    );
  }

  Future<void> _pickGalleryImage() async {
    final asset = await ChatMediaPicker.pickAsset(
      context: context,
      mode: ChatAssetPickerMode.image,
      showSnack: _showSnack,
    );
    if (asset == null) return;
    final file = await asset.file;
    if (file == null) {
      _showSnack('无法读取所选图片。');
      return;
    }

    final previewBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(512, 512),
    );

    await _sendImageFromPath(
      filePath: file.path,
      previewBytes: previewBytes,
    );
  }

  Future<void> _pickGalleryVideo() async {
    final asset = await ChatMediaPicker.pickAsset(
      context: context,
      mode: ChatAssetPickerMode.video,
      showSnack: _showSnack,
    );
    if (asset == null) return;
    final file = await asset.file;
    if (file == null) {
      _showSnack('无法读取所选视频。');
      return;
    }
    final previewBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(512, 512),
    );
    await _sendVideoFromPath(
      filePath: file.path,
      previewBytes: previewBytes,
    );
  }

  Future<void> _pickGalleryLivePhoto() async {
    final appState = context.read<AppState>();
    final asset = await ChatMediaPicker.pickAsset(
      context: context,
      mode: ChatAssetPickerMode.livePhoto,
      showSnack: _showSnack,
    );
    if (asset == null) return;

    final previewBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(512, 512),
    );

    final picked = await _dynamicMediaDetector.detect(asset);
    if (picked == null) {
      _showSnack('无法读取所选实况图片。');
      return;
    }
    final uploader = DynamicMediaUploadService(appState.files);
    await _sendDynamicPhoto(
      coverPath: picked.coverPath,
      previewBytes: previewBytes,
      upload: (userId) => uploader.upload(pickResult: picked, userId: userId),
    );
  }

  Future<void> _handleChatAction(_ChatAction action) async {
    switch (action) {
      case _ChatAction.clearConversation:
        await _clearConversation();
        break;
      case _ChatAction.clearCache:
        await _clearMediaCache();
        break;
    }
  }

  Future<void> _showChatActionsSheet() async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final button =
        _moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || button == null) return;
    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight =
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay);
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
            label: '清除缓存',
          ),
        ),
      ],
    );
    if (action != null) {
      await _handleChatAction(action);
    }
  }

  Future<void> _clearConversation() async {
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('清空聊天记录？'),
            content: const Text(
              '这会清空当前单聊的服务器聊天记录。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('清空'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      await state.messages.clearConversation(
        userId: session.userId,
        peerId: widget.peerId,
      );
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _localCoverBytesByMessageId.clear();
        _localCoverPathByMessageId.clear();
      });
      _showSnack('聊天记录已清空');
    } catch (e) {
      _showSnack(_toUserError(e));
    }
  }

  Future<void> _clearMediaCache() async {
    try {
      await MediaDownloader.clearCache();
      await DefaultCacheManager().emptyCache();
      imageCache.clear();
      imageCache.clearLiveImages();
      _showSnack('缓存已清除');
    } catch (e) {
      _showSnack(_toUserError(e));
    }
  }

  Future<void> _showAttachMenu() async {
    final action = await ChatMediaPicker.showAttachMenu(context);

    switch (action) {
      case ChatAttachAction.galleryImage:
        await _pickGalleryImage();
        break;
      case ChatAttachAction.galleryVideo:
        await _pickGalleryVideo();
        break;
      case ChatAttachAction.livePhoto:
        await _pickGalleryLivePhoto();
        break;
      case null:
        break;
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
              child: Text(
                peerName,
                overflow: TextOverflow.ellipsis,
              ),
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
                    setState(() => _error = null);
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

enum _ChatAction {
  clearConversation,
  clearCache,
}

const List<String> _emojiSet = <String>[
  '😀',
  '😁',
  '😂',
  '🤣',
  '😊',
  '😍',
  '😘',
  '😜',
  '😎',
  '🤔',
  '😴',
  '😅',
  '🤗',
  '😭',
  '😡',
  '🥳',
  '👍',
  '👌',
  '✌',
  '👏',
  '🙏',
  '🎉',
  '❤',
  '💕',
  '💯',
  '🔥',
  '🌹',
  '🍀',
  '☕',
  '🍉',
  '🎂',
  '🐶',
  '🐱',
  '🌙',
  '⭐',
];

class _MenuActionRow extends StatelessWidget {
  const _MenuActionRow({
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
