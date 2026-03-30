import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dynamic_photo_chat_flutter/models/file_upload_response.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/dynamic_photo_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/video_player_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/widgets/message_bubble.dart';
import 'package:dynamic_photo_chat_flutter/utils/live_photo_detector.dart';
import 'package:flutter/material.dart';
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
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final ImagePicker _picker = ImagePicker();

  final List<ChatMessage> _messages = [];
  final Set<int> _coverRefreshing = <int>{};
  static const int _maxConcurrentCoverRefresh = 2;
  StreamSubscription<ChatMessage>? _msgSub;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int _lastMessageId = 0;
  bool _userAtBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _msgSub = null;
    _textCtrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    final cur = _scrollCtrl.position.pixels;
    // 小阈值保证用户在“底部附近”仍允许自动滚动更新
    _userAtBottom = (max - cur) <= 80.0;
  }

  Future<void> _init() async {
    final state = context.read<AppState>();
    final session = state.session!;
    try {
      state.prefetchUser(widget.peerId);
      final history = await state.messages.history(
          userId: session.userId, peerId: widget.peerId, page: 0, size: 100);
      _messages
        ..clear()
        ..addAll(history);
      _lastMessageId = _messages.isEmpty
          ? 0
          : _messages.map((e) => e.id).reduce((a, b) => a > b ? a : b);
      await _markAllRead(session.userId);
      state.clearUnread(widget.peerId);
      _subscribeToEvents(state, session.userId);

      // 兜底：补齐历史里 VIDEO 封面（coverUrl 可能因 pending/时序未刷新）
      final pendingVideos = _messages
          .where((m) =>
              m.type.toUpperCase() == 'VIDEO' &&
              (m.coverUrl == null || m.coverUrl!.isEmpty))
          .take(3)
          .toList();
      for (final m in pendingVideos) {
        _maybeRefreshVideoCover(m);
      }
    } catch (e) {
      _error = _toUserError(e);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom();
      }
    }
  }

  void _subscribeToEvents(AppState state, int myId) {
    _msgSub?.cancel();
    _msgSub = state.messageEvents.listen((m) async {
      if (!mounted) return;
      if (m.id > _lastMessageId) _lastMessageId = m.id;
      final isInThisChat =
          (m.senderId == widget.peerId && m.receiverId == myId) ||
              (m.senderId == myId && m.receiverId == widget.peerId);
      if (!isInThisChat) return;
      final idx = _messages.indexWhere((e) => e.id == m.id);
      setState(() {
        if (idx >= 0) {
          _messages[idx] = m;
        } else {
          _messages.add(m);
          // 大多数情况下新消息 id 单调递增，不需要每次全量 sort；
          // 仅在出现异常顺序时再排序以避免展示错乱。
          if (_messages.length >= 2) {
            final last = _messages.last.id;
            final prev = _messages[_messages.length - 2].id;
            if (prev > last) {
              _messages.sort((a, b) => a.id.compareTo(b.id));
            }
          }
        }
      });
      _maybeRefreshVideoCover(m);
      if (m.senderId == widget.peerId) {
        state.clearUnread(widget.peerId);
        await _markAllRead(myId);
      }
      _scrollToBottom();
    }, onError: (e) {
      if (!mounted) return;
      setState(() => _error = _toUserError(e));
    });
  }

  String _toUserError(Object e) {
    final raw = e.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('network')) {
      return '连接失败，请在登录页右上角设置API地址为电脑局域网IP（例如 http://192.168.x.x:8080）';
    }
    return raw;
  }

  Future<void> _markAllRead(int myId) async {
    final state = context.read<AppState>();
    final unread = _messages
        .where((m) => m.receiverId == myId && (m.status ?? '') != 'READ')
        .toList();
    for (final m in unread) {
      try {
        await state.messages.markRead(m.id);
        final idx = _messages.indexWhere((e) => e.id == m.id);
        if (idx >= 0) {
          _messages[idx] = ChatMessage(
            id: m.id,
            senderId: m.senderId,
            receiverId: m.receiverId,
            type: m.type,
            content: m.content,
            resourceId: m.resourceId,
            videoResourceId: m.videoResourceId,
            coverUrl: m.coverUrl,
            videoUrl: m.videoUrl,
            status: 'READ',
            createdAt: m.createdAt,
          );
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_userAtBottom) return;
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      _scrollCtrl.jumpTo(max);
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!_userAtBottom) return;
        if (!_scrollCtrl.hasClients) return;
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      });
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        if (!_userAtBottom) return;
        if (!_scrollCtrl.hasClients) return;
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      });
    });
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    final state = context.read<AppState>();
    final session = state.session!;
    setState(() => _sending = true);
    try {
      final id = await state.messages.sendText(
          senderId: session.userId, receiverId: widget.peerId, content: text);
      _textCtrl.clear();
      final msg = ChatMessage(
        id: id,
        senderId: session.userId,
        receiverId: widget.peerId,
        type: 'TEXT',
        content: text,
        resourceId: null,
        videoResourceId: null,
        coverUrl: null,
        videoUrl: null,
        status: 'SENT',
        createdAt: DateTime.now(),
      );
      setState(() {
        _messages.add(msg);
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_sending) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('选择照片'),
                onTap: () => Navigator.of(ctx).pop('image'),
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('选择视频'),
                onTap: () => Navigator.of(ctx).pop('video'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() => _sending = true);
    try {
      if (result == 'image') {
        await _pickImage();
      } else {
        await _pickVideo();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: ${_toUserError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要相册权限')),
      );
      return;
    }

    if (!mounted) return;
    final state = context.read<AppState>();
    final session = state.session!;

    try {
      if (Platform.isIOS) {
        final asset = await _pickIosImageAsset();
        if (asset == null || !mounted) return;

        if (asset.isLivePhoto) {
          final livePhotoInfo = await LivePhotoDetector.detectLivePhoto(asset);
          if (livePhotoInfo != null) {
            final uploaded = await state.files.uploadLivePhotoAuto(
              jpegPath: livePhotoInfo.imagePath,
              movPath: livePhotoInfo.videoPath,
              userId: session.userId,
            );
            await _sendForDynamic(uploaded, session.userId);
            return;
          }
        }

        final f = await asset.file;
        if (f == null) {
          throw Exception('无法读取图片文件');
        }
        final uploaded = await state.files.uploadNormalFromPath(
          filePath: f.path,
          userId: session.userId,
        );
        await _sendForUploadedNormal(uploaded, session.userId);
        return;
      }

      if (Platform.isAndroid) {
        final pick = await _pickAndroidImage();
        if (pick == null || !mounted) return;

        final String filePath;
        if (pick.asset != null) {
          final f = await pick.asset!.file;
          if (f == null) {
            throw Exception('无法读取图片文件');
          }
          filePath = f.path;
        } else if (pick.xFile != null) {
          filePath = pick.xFile!.path;
        } else {
          return;
        }

        final isMotion =
            await LivePhotoDetector.detectMotionPhotoFromPath(filePath);
        if (!mounted) return;
        if (isMotion) {
          final uploaded = await state.files.uploadMotionPhotoFromPath(
            filePath: filePath,
            userId: session.userId,
          );
          await _sendForDynamic(uploaded, session.userId);
          return;
        }

        final uploaded = await state.files.uploadNormalFromPath(
          filePath: filePath,
          userId: session.userId,
        );
        await _sendForUploadedNormal(uploaded, session.userId);
        return;
      }

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      final uploaded = await state.files
          .uploadNormalFromXFile(file: image, userId: session.userId);
      await _sendForUploadedNormal(uploaded, session.userId);
    } catch (e) {
      rethrow;
    }
  }

  Future<AssetEntity?> _pickIosImageAsset() async {
    final paths = await PhotoManager.getAssetPathList(type: RequestType.image);
    if (paths.isEmpty || !mounted) return null;
    final path = paths.first;
    final assets = await path.getAssetListRange(start: 0, end: 200);
    if (!mounted) return null;
    return showModalBottomSheet<AssetEntity>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.85;
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
              itemBuilder: (_, i) {
                final asset = assets[i];
                return GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(asset),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FutureBuilder<Uint8List?>(
                          future: asset.thumbnailDataWithSize(
                            const ThumbnailSize(300, 300),
                          ),
                          builder: (_, snap) {
                            final data = snap.data;
                            if (data == null) {
                              return const ColoredBox(color: Colors.black12);
                            }
                            return Image.memory(data, fit: BoxFit.cover);
                          },
                        ),
                        if (asset.isLivePhoto)
                          const Positioned(
                            right: 6,
                            top: 6,
                            child: Icon(
                              Icons.motion_photos_on,
                              color: Colors.white,
                              size: 18,
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

  Future<_AndroidPick?> _pickAndroidImage() async {
    final picked = await showModalBottomSheet<_AndroidPick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.85;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: FutureBuilder<List<AssetEntity>>(
              future: _loadAndroidRecentImages(),
              builder: (_, snap) {
                final assets = snap.data;
                if (assets == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (assets.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('未找到照片'),
                          const SizedBox(height: 8),
                          const Text(
                            '如果系统权限是“仅允许部分照片”，这里可能为空；请到系统设置改为允许全部照片，或使用系统选择器。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => PhotoManager.openSetting(),
                            child: const Text('打开系统设置'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: () => Navigator.of(ctx)
                                .pop(const _AndroidPick(systemPicker: true)),
                            child: const Text('使用系统选择器'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: assets.length,
                  itemBuilder: (_, i) {
                    final asset = assets[i];
                    return GestureDetector(
                      onTap: () =>
                          Navigator.of(ctx).pop(_AndroidPick(asset: asset)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FutureBuilder<Uint8List?>(
                          future: asset.thumbnailDataWithSize(
                            const ThumbnailSize(300, 300),
                          ),
                          builder: (_, snap) {
                            final data = snap.data;
                            if (data == null) {
                              return const ColoredBox(color: Colors.black12);
                            }
                            return Image.memory(data, fit: BoxFit.cover);
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return null;
    if (!picked.systemPicker) return picked;

    final XFile? x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: null,
    );
    if (x == null || !mounted) return null;
    return _AndroidPick(xFile: x);
  }

  Future<List<AssetEntity>> _loadAndroidRecentImages() async {
    final paths = await PhotoManager.getAssetPathList(type: RequestType.image);
    for (final p in paths) {
      final assets = await p.getAssetListRange(start: 0, end: 200);
      if (assets.isNotEmpty) return assets;
    }
    return <AssetEntity>[];
  }

  Future<void> _pickVideo() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要相册权限')),
      );
      return;
    }

    final XFile? video = await _picker.pickVideo(
      source: ImageSource.gallery,
    );
    if (video == null || !mounted) return;

    final state = context.read<AppState>();
    final session = state.session!;

    try {
      final uploaded = await state.files.uploadNormalFromXFile(
        file: video,
        userId: session.userId,
      );
      await _sendForUploadedNormal(uploaded, session.userId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _sendForUploadedNormal(
      FileUploadResponse uploaded, int myId) async {
    final state = context.read<AppState>();
    final fileType = (uploaded.fileType ?? '').toUpperCase();
    if (uploaded.fileId == null) {
      throw Exception('Upload response missing fileId');
    }
    if (fileType == 'IMAGE') {
      final mid = await state.messages.sendImage(
          senderId: myId,
          receiverId: widget.peerId,
          resourceId: uploaded.fileId!);
      final msg = ChatMessage(
        id: mid,
        senderId: myId,
        receiverId: widget.peerId,
        type: 'IMAGE',
        content: null,
        resourceId: uploaded.fileId,
        videoResourceId: null,
        coverUrl: uploaded.url,
        videoUrl: null,
        status: 'SENT',
        createdAt: DateTime.now(),
      );
      setState(() => _messages.add(msg));
      _scrollToBottom();
      return;
    }

    final mid = await state.messages.sendVideo(
        senderId: myId,
        receiverId: widget.peerId,
        coverResourceId: uploaded.coverId,
        videoResourceId: uploaded.fileId!);
    final msg = ChatMessage(
      id: mid,
      senderId: myId,
      receiverId: widget.peerId,
      type: 'VIDEO',
      content: null,
      resourceId: uploaded.coverId,
      videoResourceId: uploaded.fileId,
      coverUrl: uploaded.coverUrl,
      videoUrl: uploaded.url,
      status: 'SENT',
      createdAt: DateTime.now(),
    );
    setState(() => _messages.add(msg));
    _maybeRefreshVideoCover(msg);
    _scrollToBottom();
  }

  Future<void> _sendForDynamic(FileUploadResponse uploaded, int myId) async {
    final coverId = uploaded.coverId;
    final videoId = uploaded.videoId;
    if (coverId == null || videoId == null) {
      throw Exception('Upload response missing coverId/videoId');
    }
    final state = context.read<AppState>();
    final mid = await state.messages.sendDynamicPhoto(
        senderId: myId,
        receiverId: widget.peerId,
        coverId: coverId,
        videoId: videoId);
    final msg = ChatMessage(
      id: mid,
      senderId: myId,
      receiverId: widget.peerId,
      type: 'DYNAMIC_PHOTO',
      content: null,
      resourceId: coverId,
      videoResourceId: videoId,
      coverUrl: uploaded.coverUrl,
      videoUrl: uploaded.videoUrl,
      status: 'SENT',
      createdAt: DateTime.now(),
    );
    setState(() => _messages.add(msg));
    _scrollToBottom();
  }

  void _maybeRefreshVideoCover(ChatMessage m) {
    if (m.id <= 0) return;
    if ((m.type).toUpperCase() != 'VIDEO') return;
    if (m.coverUrl != null && m.coverUrl!.isNotEmpty) return;
    final coverId = m.resourceId;
    if (coverId == null) return;
    if (_coverRefreshing.contains(m.id)) return;
    // 防止多个封面同时轮询导致网络/主线程抖动
    if (_coverRefreshing.length >= _maxConcurrentCoverRefresh) return;
    _coverRefreshing.add(m.id);
    _refreshVideoCover(messageId: m.id, coverId: coverId).whenComplete(() {
      _coverRefreshing.remove(m.id);
    });
  }

  Future<void> _refreshVideoCover(
      {required int messageId, required int coverId}) async {
    final state = context.read<AppState>();
    for (var i = 0; i < 20; i++) {
      // 前几轮 400ms 快速探测，避免首帧已就绪仍等满 2s；之后 1s 降低请求频率
      await Future<void>.delayed(
        Duration(milliseconds: i < 8 ? 400 : 1000),
      );
      if (!mounted) return;
      try {
        final info = await state.files.preview(fileId: coverId);
        final st = (info.sourceType ?? '').toUpperCase();
        final url = info.url;
        if (st != 'VIDEOCOVERPENDING' && url != null && url.isNotEmpty) {
          final idx = _messages.indexWhere((e) => e.id == messageId);
          if (idx < 0) return;
          final bust = DateTime.now().millisecondsSinceEpoch;
          final sep = url.contains('?') ? '&' : '?';
          final resolved = '$url${sep}t=$bust';
          final old = _messages[idx];
          setState(() {
            _messages[idx] = ChatMessage(
              id: old.id,
              senderId: old.senderId,
              receiverId: old.receiverId,
              type: old.type,
              content: old.content,
              resourceId: old.resourceId,
              videoResourceId: old.videoResourceId,
              coverUrl: resolved,
              videoUrl: old.videoUrl,
              status: old.status,
              createdAt: old.createdAt,
            );
          });
          return;
        }
      } catch (_) {}
    }
  }

  void _openPlayer(String url) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(url: url)));
  }

  void _openDynamicPhoto(String coverUrl, String videoUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DynamicPhotoScreen(coverUrl: coverUrl, videoUrl: videoUrl),
      ),
    );
  }

  void _openImagePreview(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
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
                      child: Text('图片加载失败',
                          style: TextStyle(color: Colors.white))),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final myId = state.session!.userId;
    final myName = state.session!.username;
    final peerName = state.displayNameFor(widget.peerId);
    final myAvatar = state.avatarUrlFor(myId);
    final peerAvatar = state.avatarUrlFor(widget.peerId);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDEDED),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(peerName),
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
                padding: const EdgeInsets.all(8),
                child:
                    Text(_error!, style: const TextStyle(color: Colors.red))),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, idx) {
                      final m = _messages[idx];
                      final isMine = m.senderId == myId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: MessageBubble(
                          message: m,
                          isMine: isMine,
                          myName: myName,
                          peerName: peerName,
                          myAvatarUrl: myAvatar,
                          peerAvatarUrl: peerAvatar,
                          onPlayVideo: _openPlayer,
                          onPreviewImage: _openImagePreview,
                          onOpenDynamicPhoto: _openDynamicPhoto,
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: const InputDecoration(
                        hintText: '输入消息',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _sendText,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('发送'),
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

class _AndroidPick {
  const _AndroidPick({this.asset, this.xFile, this.systemPicker = false});
  final AssetEntity? asset;
  final XFile? xFile;
  final bool systemPicker;
}
