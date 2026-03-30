import 'dart:async';
import 'dart:typed_data';

import 'package:dynamic_photo_chat_flutter/models/chat_media.dart';
import 'package:dynamic_photo_chat_flutter/models/file_upload_response.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/dynamic_photo_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/video_player_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/widgets/message_bubble.dart';
import 'package:dynamic_photo_chat_flutter/utils/live_photo_detector.dart';
import 'package:dynamic_photo_chat_flutter/utils/media_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
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
  final ImagePicker _picker = ImagePicker();

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
        _error = 'Please login again.';
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

  Future<void> _pickCameraImage() async {
    final file = await _picker.pickImage(source: ImageSource.camera);
    if (file == null) return;
    await _sendImageFromPath(filePath: file.path);
  }

  Future<void> _pickCameraVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.camera);
    if (file == null) return;
    await _sendVideoFromPath(filePath: file.path);
  }

  Future<void> _pickGalleryImage() async {
    final asset = await _pickAsset(AssetType.image);
    if (asset == null) return;
    final file = await asset.file;
    if (file == null) {
      _showSnack('Unable to read the selected file.');
      return;
    }

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

    final isMotion = await LivePhotoDetector.detectMotionPhoto(asset);
    if (isMotion) {
      await _sendDynamicPhoto(
        coverPath: file.path,
        previewBytes: previewBytes,
        upload: (userId) =>
            context.read<AppState>().files.uploadMotionPhotoFromPath(
                  filePath: file.path,
                  userId: userId,
                ),
      );
      return;
    }

    await _sendImageFromPath(
      filePath: file.path,
      previewBytes: previewBytes,
    );
  }

  Future<void> _pickGalleryVideo() async {
    final asset = await _pickAsset(AssetType.video);
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

  Future<AssetEntity?> _pickAsset(AssetType type) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      _showSnack('Please allow media library access first.');
      return null;
    }

    final paths = await PhotoManager.getAssetPathList(
      type: type == AssetType.video ? RequestType.video : RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(sizeConstraint: SizeConstraint()),
        videoOption: const FilterOption(sizeConstraint: SizeConstraint()),
      ),
    );
    if (paths.isEmpty) {
      _showSnack('No media found.');
      return null;
    }

    final assets = await paths.first.getAssetListPaged(page: 0, size: 120);
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
                        FutureBuilder<Uint8List?>(
                          future: asset.thumbnailDataWithSize(
                            const ThumbnailSize(300, 300),
                          ),
                          builder: (_, snapshot) {
                            final data = snapshot.data;
                            if (data == null) {
                              return const ColoredBox(color: Colors.black12);
                            }
                            return Image.memory(data, fit: BoxFit.cover);
                          },
                        ),
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

  void _openPlayer(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(url: url),
      ),
    );
  }

  void _openDynamicPhoto(String coverUrl, String videoUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DynamicPhotoScreen(coverUrl: coverUrl, videoUrl: videoUrl),
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

  Future<void> _clearConversation() async {
    final state = context.read<AppState>();
    final session = state.session;
    if (session == null) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Clear chat history?'),
            content: const Text(
              'This will remove the current one-to-one conversation history from the server.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Clear'),
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
      _showSnack('Media cache cleared.');
    } catch (e) {
      _showSnack(_toUserError(e));
    }
  }

  void _openImagePreview(String url) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Stack(
          children: [
            Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text(
                      'Image failed to load.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAttachMenu() async {
    final action = await showModalBottomSheet<_AttachAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Gallery Photo'),
                onTap: () => Navigator.of(sheetContext).pop(_AttachAction.galleryImage),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Gallery Video'),
                onTap: () => Navigator.of(sheetContext).pop(_AttachAction.galleryVideo),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Camera Photo'),
                onTap: () => Navigator.of(sheetContext).pop(_AttachAction.cameraImage),
              ),
              ListTile(
                leading: const Icon(Icons.video_call_outlined),
                title: const Text('Camera Video'),
                onTap: () => Navigator.of(sheetContext).pop(_AttachAction.cameraVideo),
              ),
              const SizedBox(height: 8),
            ],
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
      case _AttachAction.cameraImage:
        await _pickCameraImage();
        break;
      case _AttachAction.cameraVideo:
        await _pickCameraVideo();
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(peerName),
            Text(
              'ID ${widget.peerId}',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Colors.black54),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_ChatAction>(
            onSelected: _handleChatAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ChatAction.clearConversation,
                child: Text('Clear chat history'),
              ),
              PopupMenuItem(
                value: _ChatAction.clearCache,
                child: Text('Clear cache'),
              ),
            ],
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
                  child: const Text('Retry'),
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
                      return MessageBubble(
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
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sending ? null : _showAttachMenu,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _sendText,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send'),
                  ),
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
  cameraImage,
  cameraVideo,
}

enum _ChatAction {
  clearConversation,
  clearCache,
}
