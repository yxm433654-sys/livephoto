import 'dart:async';
import 'dart:io';

import 'package:dynamic_photo_chat_flutter/models/file_upload_response.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/services/realtime_service.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/video_player_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/widgets/dynamic_photo_picker.dart';
import 'package:dynamic_photo_chat_flutter/ui/widgets/message_bubble.dart';
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
  final _imagePicker = ImagePicker();

  final List<ChatMessage> _messages = [];
  RealtimeService? _realtime;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int _lastMessageId = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _realtime?.stop();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final state = context.read<AppState>();
    final session = state.session!;
    try {
      final history = await state.messages.history(
          userId: session.userId, peerId: widget.peerId, page: 0, size: 100);
      _messages
        ..clear()
        ..addAll(history);
      _lastMessageId = _messages.isEmpty
          ? 0
          : _messages.map((e) => e.id).reduce((a, b) => a > b ? a : b);
      await _markAllRead(session.userId);
      _startRealtime();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom();
      }
    }
  }

  void _startRealtime() {
    final state = context.read<AppState>();
    final session = state.session!;
    final rt = RealtimeService(state.messages, wsBaseUrl: state.wsBaseUrl);
    rt.start(
      userId: session.userId,
      token: session.token,
      lastMessageId: _lastMessageId,
      onMessage: (m) async {
        if (m.id > _lastMessageId) _lastMessageId = m.id;
        if (m.senderId != widget.peerId) return;
        if (_messages.any((e) => e.id == m.id)) return;
        setState(() {
          _messages.add(m);
          _messages.sort((a, b) => a.id.compareTo(b.id));
        });
        await _markAllRead(session.userId);
        _scrollToBottom();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      },
    );
    _realtime = rt;
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
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ─── 发送文本 ───

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
        _messages.sort((a, b) => a.id.compareTo(b.id));
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

  // ─── 从相册选择并上传图片 ───

  Future<void> _pickAndSendImage() async {
    final xfile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xfile == null || !mounted) return;
    final state = context.read<AppState>();
    final session = state.session!;
    setState(() => _sending = true);
    try {
      final uploaded = await state.files.uploadNormalByPath(
        filePath: xfile.path,
        fileName: xfile.name,
        userId: session.userId,
      );
      await _sendForUploadedNormal(uploaded, session.userId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ─── 从相册选择并上传视频 ───

  Future<void> _pickAndSendVideo() async {
    final xfile = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (xfile == null || !mounted) return;
    final state = context.read<AppState>();
    final session = state.session!;
    setState(() => _sending = true);
    try {
      final uploaded = await state.files.uploadNormalByPath(
        filePath: xfile.path,
        fileName: xfile.name,
        userId: session.userId,
      );
      await _sendForUploadedNormal(uploaded, session.userId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 处理普通图片/视频上传结果并发送消息
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
        videoResourceId: uploaded.fileId!);
    final msg = ChatMessage(
      id: mid,
      senderId: myId,
      receiverId: widget.peerId,
      type: 'VIDEO',
      content: null,
      resourceId: null,
      videoResourceId: uploaded.fileId,
      coverUrl: null,
      videoUrl: uploaded.url,
      status: 'SENT',
      createdAt: DateTime.now(),
    );
    setState(() => _messages.add(msg));
    _scrollToBottom();
  }

  // ─── 从相册选择并上传动态照片（iOS Live Photo / Android Motion Photo）───

  Future<void> _pickAndSendDynamicPhoto() async {
    // 使用 photo_manager 的选择器, 让用户从相册选一张图片
    final asset = await DynamicPhotoPickerDialog.pick(context);
    if (asset == null || !mounted) return;

    final state = context.read<AppState>();
    final session = state.session!;
    setState(() => _sending = true);

    try {
      if (Platform.isIOS) {
        await _uploadIOSDynamicPhoto(asset, state, session.userId);
      } else {
        await _uploadAndroidDynamicPhoto(asset, state, session.userId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// iOS: 获取 Live Photo 的图片和视频，上传到 /upload/live-photo
  Future<void> _uploadIOSDynamicPhoto(
      AssetEntity asset, AppState state, int myId) async {
    // 获取原始图片文件
    final File? imageFile = await asset.originFile;
    if (imageFile == null) {
      throw Exception('无法加载图片文件');
    }

    // 尝试获取 Live Photo 的视频部分
    // iOS Live Photo 的 subtype 包含 (subtype & 8) != 0
    final bool isLivePhoto = (asset.subtype & 8) != 0;

    if (isLivePhoto) {
      // 获取关联视频的 URL
      final String? videoUrl = await asset.getMediaUrl();
      if (videoUrl != null) {
        final videoPath = Uri.parse(videoUrl).toFilePath();
        final uploaded = await state.files.uploadLivePhotoByPath(
          jpegPath: imageFile.path,
          jpegName: asset.title ?? 'photo.jpg',
          videoPath: videoPath,
          videoName: '${asset.title ?? "live"}.mov',
          userId: myId,
        );
        await _sendForDynamic(uploaded, myId);
        return;
      }
    }

    // 不是 Live Photo 或无法获取视频，尝试作为 Motion Photo 上传
    final uploaded = await state.files.uploadMotionPhotoByPath(
      filePath: imageFile.path,
      fileName: asset.title ?? 'photo.jpg',
      userId: myId,
    );
    await _sendForDynamic(uploaded, myId);
  }

  /// Android: 获取原始文件，上传到 /upload/motion-photo
  Future<void> _uploadAndroidDynamicPhoto(
      AssetEntity asset, AppState state, int myId) async {
    final File? file = await asset.originFile;
    if (file == null) {
      throw Exception('无法加载图片文件');
    }

    final uploaded = await state.files.uploadMotionPhotoByPath(
      filePath: file.path,
      fileName: asset.title ?? 'photo.jpg',
      userId: myId,
    );
    await _sendForDynamic(uploaded, myId);
  }

  /// 处理动态照片上传结果并发送消息
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

  void _openPlayer(String url) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(url: url)));
  }

  // ─── 附件菜单 ───

  Future<void> _showAttachMenu() async {
    if (_sending) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('发送图片'),
                subtitle: const Text('从相册选择图片'),
                onTap: () => Navigator.of(ctx).pop('image'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('发送视频'),
                subtitle: const Text('从相册选择视频'),
                onTap: () => Navigator.of(ctx).pop('video'),
              ),
              ListTile(
                leading: const Icon(Icons.motion_photos_on_outlined),
                title: const Text('发送动态照片'),
                subtitle: const Text('Live Photo / Motion Photo'),
                onTap: () => Navigator.of(ctx).pop('dynamic'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    if (action == 'image') return _pickAndSendImage();
    if (action == 'video') return _pickAndSendVideo();
    if (action == 'dynamic') return _pickAndSendDynamicPhoto();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final myId = state.session!.userId;
    return Scaffold(
      appBar: AppBar(
        title: Text('与用户 ${widget.peerId} 聊天'),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, idx) {
                      final m = _messages[idx];
                      final isMine = m.senderId == myId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: MessageBubble(
                          message: m,
                          isMine: isMine,
                          onPlayVideo: _openPlayer,
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _showAttachMenu,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: const InputDecoration(
                        hintText: '输入消息',
                        border: OutlineInputBorder(),
                        isDense: true,
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
