import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:dynamic_photo_chat_flutter/models/chat_media.dart';
import 'package:dynamic_photo_chat_flutter/models/file_upload_response.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/dynamic_photo_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/image_preview_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/video_player_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/widgets/message_bubble.dart';
import 'package:dynamic_photo_chat_flutter/utils/live_photo_detector.dart';
import 'package:dynamic_photo_chat_flutter/utils/media_downloader.dart';
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
      setState(() {
        if (idx >= 0) {
          _messages[idx] = message;
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
    final text = error.toString().trim();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
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

  ChatMessage _buildLocalMessage({
    required int id,
    required int senderId,
    required String type,
    String? content,
    int? resourceId,
    int? videoResourceId,
    String? coverUrl,
    String? videoUrl,
    ChatMedia? media,
    String? status,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      receiverId: widget.peerId,
      type: type,
      content: content,
      resourceId: resourceId,
      videoResourceId: videoResourceId,
      coverUrl: coverUrl,
      videoUrl: videoUrl,
      media: media,
      status: status,
      createdAt: DateTime.now(),
    );
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
    final hasRemoteCover =
        (message.media?.coverUrl ?? message.coverUrl)?.trim().isNotEmpty == true;
    final hasRemoteImage =
        (message.media?.coverUrl ?? message.coverUrl)?.trim().isNotEmpty == true;
    final hasRemoteVideo =
        (message.media?.playUrl ?? message.videoUrl)?.trim().isNotEmpty == true;
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

  ChatMedia _buildImageMedia(FileUploadResponse upload) {
    return ChatMedia(
      mediaKind: 'IMAGE',
      processingStatus: 'READY',
      resourceId: upload.fileId,
      coverResourceId: upload.fileId,
      playResourceId: upload.fileId,
      coverUrl: upload.url,
      playUrl: upload.url,
      width: upload.width,
      height: upload.height,
      duration: upload.duration,
      aspectRatio: _aspectRatio(upload.width, upload.height, 1.0),
      sourceType: upload.sourceType,
    );
  }

  ChatMedia _buildVideoMedia(
    FileUploadResponse upload, {
    String processingStatus = 'PROCESSING',
  }) {
    final coverId = upload.coverId;
    final playId = upload.videoId ?? upload.fileId;
    return ChatMedia(
      mediaKind: 'VIDEO',
      processingStatus: processingStatus,
      resourceId: playId,
      coverResourceId: coverId,
      playResourceId: playId,
      coverUrl: upload.coverUrl,
      playUrl: upload.videoUrl ?? upload.url,
      width: upload.width,
      height: upload.height,
      duration: upload.duration,
      aspectRatio: _aspectRatio(upload.width, upload.height, 9 / 16),
      sourceType: upload.sourceType,
    );
  }

  ChatMedia _buildDynamicMedia(
    FileUploadResponse upload, {
    String processingStatus = 'PROCESSING',
  }) {
    return ChatMedia(
      mediaKind: 'DYNAMIC_PHOTO',
      processingStatus: processingStatus,
      resourceId: upload.coverId,
      coverResourceId: upload.coverId,
      playResourceId: upload.videoId,
      coverUrl: upload.coverUrl,
      playUrl: upload.videoUrl,
      width: upload.width,
      height: upload.height,
      duration: upload.duration,
      aspectRatio: _aspectRatio(upload.width, upload.height, 3 / 4),
      sourceType: upload.sourceType,
    );
  }

  double _aspectRatio(int? width, int? height, double fallback) {
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return fallback;
  }

  Future<void> _sendText() async {
    if (_sending) return;
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) return;

    final tempId = _nextTempId();
    final tempMessage = _buildLocalMessage(
      id: tempId,
      senderId: session.userId,
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
      _replaceMessage(
        tempId,
        _buildLocalMessage(
          id: messageId,
          senderId: session.userId,
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
    if (_sending) return;
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) return;

    final tempId = _nextTempId();
    final tempMessage = _buildLocalMessage(
      id: tempId,
      senderId: session.userId,
      type: 'IMAGE',
      media: ChatMedia(
        mediaKind: 'IMAGE',
        processingStatus: 'PROCESSING',
        resourceId: null,
        coverResourceId: null,
        playResourceId: null,
        coverUrl: null,
        playUrl: null,
        width: null,
        height: null,
        duration: null,
        aspectRatio: 1.0,
        sourceType: null,
      ),
      status: 'SENDING',
    );
    _insertLocalMessage(
      tempMessage,
      localCoverBytes: previewBytes,
      localCoverPath: filePath,
    );

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final upload = await state.files.uploadNormalFromPath(
        filePath: filePath,
        userId: session.userId,
      );
      final media = _buildImageMedia(upload);
      final messageId = await state.messages.sendImage(
        senderId: session.userId,
        receiverId: widget.peerId,
        resourceId: upload.fileId!,
      );
      _replaceMessage(
        tempId,
        _buildLocalMessage(
          id: messageId,
          senderId: session.userId,
          type: 'IMAGE',
          resourceId: upload.fileId,
          coverUrl: upload.url,
          videoUrl: upload.url,
          media: media,
          status: 'SENT',
        ),
      );
    } catch (e) {
      _removeLocalMessage(tempId);
      _showSnack(_toUserError(e));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendVideoFromPath({
    required String filePath,
    Uint8List? previewBytes,
  }) async {
    if (_sending) return;
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) return;

    final tempId = _nextTempId();
    final tempMessage = _buildLocalMessage(
      id: tempId,
      senderId: session.userId,
      type: 'VIDEO',
      media: ChatMedia(
        mediaKind: 'VIDEO',
        processingStatus: 'PROCESSING',
        resourceId: null,
        coverResourceId: null,
        playResourceId: null,
        coverUrl: null,
        playUrl: null,
        width: null,
        height: null,
        duration: null,
        aspectRatio: 9 / 16,
        sourceType: null,
      ),
      status: 'SENDING',
    );
    _insertLocalMessage(
      tempMessage,
      localCoverBytes: previewBytes,
    );

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final upload = await state.files.uploadNormalFromPath(
        filePath: filePath,
        userId: session.userId,
      );
      final playId = upload.videoId ?? upload.fileId;
      if (playId == null) {
        throw Exception('Video upload did not return a resource id.');
      }
      final messageId = await state.messages.sendVideo(
        senderId: session.userId,
        receiverId: widget.peerId,
        videoResourceId: playId,
        coverResourceId: upload.coverId,
      );
      _replaceMessage(
        tempId,
        _buildLocalMessage(
          id: messageId,
          senderId: session.userId,
          type: 'VIDEO',
          resourceId: upload.coverId,
          videoResourceId: playId,
          coverUrl: upload.coverUrl,
          videoUrl: upload.videoUrl ?? upload.url,
          media: _buildVideoMedia(upload),
          status: 'SENT',
        ),
      );
    } catch (e) {
      _removeLocalMessage(tempId);
      _showSnack(_toUserError(e));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendDynamicPhoto({
    required String coverPath,
    Uint8List? previewBytes,
    required Future<FileUploadResponse> Function(int userId) upload,
  }) async {
    if (_sending) return;
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) return;

    final tempId = _nextTempId();
    final tempMessage = _buildLocalMessage(
      id: tempId,
      senderId: session.userId,
      type: 'DYNAMIC_PHOTO',
      media: ChatMedia(
        mediaKind: 'DYNAMIC_PHOTO',
        processingStatus: 'PROCESSING',
        resourceId: null,
        coverResourceId: null,
        playResourceId: null,
        coverUrl: null,
        playUrl: null,
        width: null,
        height: null,
        duration: null,
        aspectRatio: 3 / 4,
        sourceType: null,
      ),
      status: 'SENDING',
    );
    _insertLocalMessage(
      tempMessage,
      localCoverBytes: previewBytes,
      localCoverPath: coverPath,
    );

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final uploaded = await upload(session.userId);
      if (uploaded.coverId == null || uploaded.videoId == null) {
        throw Exception('Dynamic photo upload did not return full resources.');
      }
      final messageId = await state.messages.sendDynamicPhoto(
        senderId: session.userId,
        receiverId: widget.peerId,
        coverId: uploaded.coverId!,
        videoId: uploaded.videoId!,
      );
      _replaceMessage(
        tempId,
        _buildLocalMessage(
          id: messageId,
          senderId: session.userId,
          type: 'DYNAMIC_PHOTO',
          resourceId: uploaded.coverId,
          videoResourceId: uploaded.videoId,
          coverUrl: uploaded.coverUrl,
          videoUrl: uploaded.videoUrl,
          media: _buildDynamicMedia(uploaded),
          status: 'SENT',
        ),
      );
    } catch (e) {
      _removeLocalMessage(tempId);
      _showSnack(_toUserError(e));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _pickGalleryImage() async {
    final asset = await _pickAsset(_AssetPickerMode.image);
    if (asset == null) return;
    final file = await asset.file;
    if (file == null) {
      _showSnack('Unable to read the selected file.');
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
    final asset = await _pickAsset(_AssetPickerMode.video);
    if (asset == null) return;
    final file = await asset.file;
    if (file == null) {
      _showSnack('Unable to read the selected file.');
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
    final asset = await _pickAsset(_AssetPickerMode.livePhoto);
    if (asset == null) return;

    final previewBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(512, 512),
    );

    final live = await LivePhotoDetector.detectLivePhoto(asset);
    if (live != null) {
      await _sendDynamicPhoto(
        coverPath: live.imagePath,
        previewBytes: previewBytes,
        upload: (userId) => context.read<AppState>().files.uploadLivePhotoAuto(
              jpegPath: live.imagePath,
              movPath: live.videoPath,
              userId: userId,
            ),
      );
      return;
    }

    final file = await asset.file;
    if (file == null) {
      _showSnack('Unable to read the selected live photo.');
      return;
    }

    await _sendDynamicPhoto(
      coverPath: file.path,
      previewBytes: previewBytes,
      upload: (userId) => context.read<AppState>().files.uploadMotionPhotoFromPath(
            filePath: file.path,
            userId: userId,
          ),
    );
  }

  Future<AssetEntity?> _pickAsset(_AssetPickerMode mode) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      _showSnack('请先允许访问媒体库');
      return null;
    }

    final paths = await PhotoManager.getAssetPathList(
      type: mode == _AssetPickerMode.video ? RequestType.video : RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(sizeConstraint: SizeConstraint()),
        videoOption: const FilterOption(sizeConstraint: SizeConstraint()),
      ),
    );
    if (paths.isEmpty) {
      _showSnack('没有找到媒体内容');
      return null;
    }

    final rawAssets = await paths.first.getAssetListPaged(page: 0, size: 96);
    final assets = await _filterAssetsForMode(rawAssets, mode);
    if (assets.isEmpty) {
      if (!mounted) return null;
      _showSnack(_pickerEmptyMessage(mode));
      return null;
    }
    if (!mounted) return null;

    return showModalBottomSheet<AssetEntity>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final height = MediaQuery.of(sheetContext).size.height * 0.8;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: assets.length,
              itemBuilder: (_, index) {
                final asset = assets[index];
                return GestureDetector(
                  onTap: () => Navigator.of(sheetContext).pop(asset),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _AssetThumbnail(asset: asset),
                        if (asset.type == AssetType.video)
                          const Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.play_circle_fill,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (mode == _AssetPickerMode.livePhoto)
                          const Positioned(
                            top: 6,
                            left: 6,
                            child: _AssetLiveBadge(),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<List<AssetEntity>> _filterAssetsForMode(
    List<AssetEntity> assets,
    _AssetPickerMode mode,
  ) async {
    if (mode == _AssetPickerMode.video) {
      return assets.where((asset) => asset.type == AssetType.video).toList();
    }

    final imageAssets =
        assets.where((asset) => asset.type == AssetType.image).toList();
    if (Platform.isIOS) {
      return imageAssets.where((asset) {
        final isLive = asset.isLivePhoto;
        return mode == _AssetPickerMode.livePhoto ? isLive : !isLive;
      }).toList();
    }
    if (Platform.isAndroid && mode == _AssetPickerMode.image) {
      return imageAssets;
    }

    final filtered = <AssetEntity>[];
    for (final asset in imageAssets.take(90)) {
      final isDynamic = await _isDynamicAsset(asset);
      if (mode == _AssetPickerMode.livePhoto && isDynamic) {
        filtered.add(asset);
      } else if (mode == _AssetPickerMode.image && !isDynamic) {
        filtered.add(asset);
      }
    }
    return filtered;
  }

  Future<bool> _isDynamicAsset(AssetEntity asset) async {
    if (Platform.isIOS) {
      return asset.isLivePhoto;
    }
    if (Platform.isAndroid) {
      return LivePhotoDetector.detectMotionPhoto(asset);
    }
    return false;
  }

  String _pickerEmptyMessage(_AssetPickerMode mode) {
    switch (mode) {
      case _AssetPickerMode.image:
        return '没有找到图片';
      case _AssetPickerMode.video:
        return '没有找到视频';
      case _AssetPickerMode.livePhoto:
        return '没有找到 Live Photo';
    }
  }

  void _openPlayer(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(url: url),
      ),
    );
  }

  Future<void> _openDynamicPhoto(
    String coverUrl,
    String videoUrl,
    double aspectRatio,
  ) async {
    if (coverUrl.trim().isNotEmpty) {
      await precacheImage(NetworkImage(coverUrl), context);
      if (!mounted) return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DynamicPhotoScreen(
          coverUrl: coverUrl,
          videoUrl: videoUrl,
          initialAspectRatio: aspectRatio,
        ),
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
      _showSnack('Chat history cleared.');
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

  void _openImagePreview(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImagePreviewScreen(url: url),
      ),
    );
  }

  Future<void> _showAttachMenu() async {
    final action = await showModalBottomSheet<_AttachAction>(
      context: context,
      backgroundColor: const Color(0xFFF7F8FA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '发送媒体',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _AttachTile(
                      icon: Icons.image_outlined,
                      label: '图片',
                      color: const Color(0xFFE0F2FE),
                      iconColor: const Color(0xFF0284C7),
                      onTap: () =>
                          Navigator.of(sheetContext).pop(_AttachAction.galleryImage),
                    ),
                    _AttachTile(
                      icon: Icons.smart_display_outlined,
                      label: '视频',
                      color: const Color(0xFFDCFCE7),
                      iconColor: const Color(0xFF16A34A),
                      onTap: () =>
                          Navigator.of(sheetContext).pop(_AttachAction.galleryVideo),
                    ),
                    _AttachTile(
                      icon: Icons.motion_photos_on_outlined,
                      label: 'Live Photo',
                      color: const Color(0xFFFCE7F3),
                      iconColor: const Color(0xFFDB2777),
                      onTap: () =>
                          Navigator.of(sheetContext).pop(_AttachAction.livePhoto),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    switch (action) {
      case _AttachAction.galleryImage:
        await _pickGalleryImage();
        break;
      case _AttachAction.galleryVideo:
        await _pickGalleryVideo();
        break;
      case _AttachAction.livePhoto:
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMine = message.senderId == myId;
                      return Column(
                        children: [
                          if (_shouldShowTimestamp(index))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE5E7EB),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _formatTimestamp(message.createdAt),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          MessageBubble(
                            message: message,
                            isMine: isMine,
                            myName: myName,
                            peerName: peerName,
                            myAvatarUrl: myAvatarUrl,
                            peerAvatarUrl: peerAvatarUrl,
                            onPlayVideo: _openPlayer,
                            onPreviewImage: _openImagePreview,
                            onOpenDynamicPhoto: _openDynamicPhoto,
                            localCoverBytes:
                                _localCoverBytesByMessageId[message.id],
                            localCoverPath:
                                _localCoverPathByMessageId[message.id],
                          ),
                        ],
                      );
                    },
                  ),
          ),
          SafeArea(
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
                        onTap: _sending ? null : _showAttachMenu,
                      ),
                      const SizedBox(width: 8),
                      _ComposerIconButton(
                        icon: Icons.sentiment_satisfied_alt_rounded,
                        onTap: _toggleEmojiPanel,
                        active: _showEmojiPanel,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
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
                            controller: _textCtrl,
                            focusNode: _textFocusNode,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onTap: () {
                              if (_showEmojiPanel) {
                                setState(() => _showEmojiPanel = false);
                              }
                            },
                            onSubmitted: (_) => _sendText(),
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
                        onPressed: _sending ? null : _sendText,
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
                  if (_showEmojiPanel) ...[
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
                        children: _emojiSet
                            .map(
                              (emoji) => InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _appendEmoji(emoji),
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
          ),
        ],
      ),
    );
  }
}

enum _AttachAction {
  galleryImage,
  galleryVideo,
  livePhoto,
}

enum _AssetPickerMode {
  image,
  video,
  livePhoto,
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
  '🥹',
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
  '✌️',
  '👏',
  '🙏',
  '🎉',
  '❤️',
  '💖',
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

class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
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

class _AssetThumbnail extends StatelessWidget {
  const _AssetThumbnail({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize(220, 220)),
      builder: (_, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const ColoredBox(color: Color(0xFFF3F4F6));
        }
        return Image.memory(
          data,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        );
      },
    );
  }
}

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

class _AssetLiveBadge extends StatelessWidget {
  const _AssetLiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 3.5,
            backgroundColor: Color(0xFFFF4D4F),
          ),
          SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
