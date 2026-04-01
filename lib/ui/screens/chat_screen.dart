import 'dart:async';
import 'dart:typed_data';

import 'package:dynamic_photo_chat_flutter/application/message/chat_conversation_coordinator.dart';
import 'package:dynamic_photo_chat_flutter/models/file_upload_response.dart';
import 'package:dynamic_photo_chat_flutter/models/media_draft_metadata.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/platform/dynamic/dynamic_photo_adapter.dart';
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
  final ChatConversationCoordinator _conversationCoordinator =
      const ChatConversationCoordinator();

  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<int, Uint8List> _localCoverBytesByMessageId = <int, Uint8List>{};
  final Map<int, String> _localCoverPathByMessageId = <int, String>{};
  ChatMediaNavigator? _chatMediaNavigator;
  final DynamicPhotoAdapter _dynamicPhotoAdapter = const DynamicPhotoAdapter();

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

    final conversationState = await _conversationCoordinator.initialize(
      appState: state,
      currentUserId: session.userId,
      peerId: widget.peerId,
    );

    _messages
      ..clear()
      ..addAll(conversationState.messages);
    _lastMessageId = conversationState.lastMessageId;
    _error = conversationState.errorMessage;
    _subscribeToEvents(state, session.userId);

    if (mounted) {
      setState(() => _loading = false);
      _scrollToBottom(animated: false);
    }
  }

  void _subscribeToEvents(AppState state, int myId) {
    _msgSub?.cancel();
    _msgSub = state.messageEvents.listen((message) async {
      if (!mounted) return;

      final pendingIdBefore = _findPendingIdForIncoming(message, myId);
      final update = await _conversationCoordinator.applyIncomingMessage(
        appState: state,
        currentMessages: _messages,
        incomingMessage: message,
        currentUserId: myId,
        peerId: widget.peerId,
        userAtBottom: _userAtBottom,
      );
      if (update == null) return;

      setState(() {
        _messages
          ..clear()
          ..addAll(update.messages);
        if (pendingIdBefore != null) {
          final localBytes = _localCoverBytesByMessageId.remove(pendingIdBefore);
          final localPath = _localCoverPathByMessageId.remove(pendingIdBefore);
          if (localBytes != null) {
            _localCoverBytesByMessageId[message.id] = localBytes;
          }
          if (localPath != null) {
            _localCoverPathByMessageId[message.id] = localPath;
          }
        }
        if (update.lastMessageId > _lastMessageId) {
          _lastMessageId = update.lastMessageId;
        }
        _dropLocalPreviewIfRemoteReady(message);
      });

      if (update.shouldScrollToBottom) {
        _scrollToBottom();
      }
    });
  }

  int? _findPendingIdForIncoming(ChatMessage message, int myId) {
    final index = _conversationCoordinator.findPendingLocalIndex(
      _messages,
      message,
      myId,
      widget.peerId,
    );
    return index >= 0 ? _messages[index].id : null;
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

  MessageSender _messageSender(AppState state, int senderId) {
    return MessageSender(
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
      _messages.sort(_conversationCoordinator.compareMessages);
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
      _messages.sort(_conversationCoordinator.compareMessages);
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
      onQueued: () {
        _textCtrl.clear();
      },
      onFailedRestore: (failedText) {
        _textCtrl.text = failedText;
      },
    );
  }

  Future<void> _sendImageFromPath({
    required String filePath,
    Uint8List? previewBytes,
    MediaDraftMetadata? metadata,
  }) async {
    final state = context.read<AppState>();
    final session = state.session;
    if (_sending || session == null) return;
    await _messageSender(state, session.userId).sendImageFromPath(
      filePath: filePath,
      previewBytes: previewBytes,
      metadata: metadata,
    );
  }

  Future<void> _sendVideoFromPath({
    required String filePath,
    Uint8List? previewBytes,
    MediaDraftMetadata? metadata,
  }) async {
    final state = context.read<AppState>();
    final session = state.session;
    if (_sending || session == null) return;
    await _messageSender(state, session.userId).sendVideoFromPath(
      filePath: filePath,
      previewBytes: previewBytes,
      metadata: metadata,
    );
  }

  Future<void> _sendDynamicPhoto({
    required String coverPath,
    Uint8List? previewBytes,
    required Future<FileUploadResponse> Function(int userId) upload,
    MediaDraftMetadata? metadata,
  }) async {
    final state = context.read<AppState>();
    final session = state.session;
    if (_sending || session == null) return;
    await _messageSender(state, session.userId).sendDynamicPhoto(
      coverPath: coverPath,
      previewBytes: previewBytes,
      upload: upload,
      metadata: metadata,
    );
  }

  Future<void> _pickGalleryImage() async {
    final asset = await ChatMediaPicker.pickAsset(
      context: context,
      mode: ChatAssetPickerMode.image,
      showSnack: _showSnack,
    );
    if (asset == null) return;
    final file = await asset.originFile ?? await asset.file;
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
      metadata: MediaDraftMetadata(
        width: asset.width,
        height: asset.height,
      ),
    );
  }

  Future<void> _pickGalleryVideo() async {
    final asset = await ChatMediaPicker.pickAsset(
      context: context,
      mode: ChatAssetPickerMode.video,
      showSnack: _showSnack,
    );
    if (asset == null) return;
    final file = await asset.originFile ?? await asset.file;
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
      metadata: MediaDraftMetadata(
        width: asset.width,
        height: asset.height,
        durationSeconds: asset.duration.toDouble(),
      ),
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

    final picked = await _dynamicPhotoAdapter.detect(asset);
    if (picked == null) {
      _showSnack('无法读取所选实况图片。');
      return;
    }
    final uploader = DynamicMediaUploadService(appState.files);
    await _sendDynamicPhoto(
      coverPath: picked.coverPath,
      previewBytes: previewBytes,
      upload: (userId) => uploader.upload(pickResult: picked, userId: userId),
      metadata: MediaDraftMetadata(
        width: asset.width,
        height: asset.height,
        durationSeconds: asset.duration.toDouble(),
      ),
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
