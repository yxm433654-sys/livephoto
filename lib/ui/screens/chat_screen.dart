import 'package:dynamic_photo_chat_flutter/models/file_upload_response.dart';
import 'package:dynamic_photo_chat_flutter/models/message.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:dynamic_photo_chat_flutter/ui/screens/video_player_screen.dart';
import 'package:dynamic_photo_chat_flutter/ui/widgets/message_bubble.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int _lastMessageId = 0;

  late final AppState _appState;
  VoidCallback? _appListener;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>();
    _appListener = _onAppStateChanged;
    _appState.addListener(_appListener!);
    _init();
  }

  @override
  void dispose() {
    if (_appListener != null) {
      _appState.removeListener(_appListener!);
      _appListener = null;
    }
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final session = _appState.session!;
    try {
      final history = await _appState.messages.history(
        userId: session.userId,
        peerId: widget.peerId,
        page: 0,
        size: 100,
      );
      _messages
        ..clear()
        ..addAll(history);
      _lastMessageId = _messages.isEmpty ? 0 : _messages.map((e) => e.id).reduce((a, b) => a > b ? a : b);
      await _markAllRead(session.userId);
      await _appState.markPeerRead(widget.peerId);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom();
      }
    }
  }

  void _onAppStateChanged() {
    final session = _appState.session;
    if (session == null) return;
    final last = _appState.lastMessageByPeer[widget.peerId];
    if (last == null) return;
    if (_messages.any((e) => e.id == last.id)) return;

    if (last.id > _lastMessageId) _lastMessageId = last.id;
    if (!mounted) return;
    setState(() {
      _messages.add(last);
      _messages.sort((a, b) => a.id.compareTo(b.id));
    });

    if (last.receiverId == session.userId && (last.status ?? '') != 'READ') {
      _appState.messages.markRead(last.id).then((_) => _appState.markPeerRead(widget.peerId));
    } else {
      _appState.markPeerRead(widget.peerId);
    }
    _scrollToBottom();
  }

  Future<void> _markAllRead(int myId) async {
    final unread = _messages.where((m) => m.receiverId == myId && (m.status ?? '') != 'READ').toList();
    for (final m in unread) {
      try {
        await _appState.messages.markRead(m.id);
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
    await _appState.markPeerRead(widget.peerId);
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

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    final session = _appState.session!;
    setState(() => _sending = true);
    try {
      final id = await _appState.messages.sendText(
        senderId: session.userId,
        receiverId: widget.peerId,
        content: text,
      );
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
      _appState.recordLocalMessage(msg);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndUploadNormal() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'heic', 'mp4', 'mov'],
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;
    final session = _appState.session!;
    setState(() => _sending = true);
    try {
      final uploaded = await _appState.files.uploadNormal(file: result.files.first, userId: session.userId);
      await _sendForUploadedNormal(uploaded, session.userId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendForUploadedNormal(FileUploadResponse uploaded, int myId) async {
    final fileType = (uploaded.fileType ?? '').toUpperCase();
    if (uploaded.fileId == null) {
      throw Exception('Upload response missing fileId');
    }

    if (fileType == 'IMAGE') {
      final mid = await _appState.messages.sendImage(
        senderId: myId,
        receiverId: widget.peerId,
        resourceId: uploaded.fileId!,
      );
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
      _appState.recordLocalMessage(msg);
      _scrollToBottom();
      return;
    }

    final mid = await _appState.messages.sendVideo(
      senderId: myId,
      receiverId: widget.peerId,
      videoResourceId: uploaded.fileId!,
    );
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
    _appState.recordLocalMessage(msg);
    _scrollToBottom();
  }

  Future<void> _pickAndUploadLivePhoto() async {
    // ── 步骤 0：引导对话框 ──
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.motion_photos_on_outlined, size: 40),
        title: const Text('上传 Live Photo'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'iOS Live Photo 由两个文件组成，请在接下来的两步中分别选择：',
              style: TextStyle(height: 1.5),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  child: Text('1', style: TextStyle(fontSize: 11)),
                ),
                SizedBox(width: 10),
                Text('JPEG 照片文件（.jpg / .jpeg）'),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  child: Text('2', style: TextStyle(fontSize: 11)),
                ),
                SizedBox(width: 10),
                Text('MOV/MP4 视频文件（.mov / .mp4）'),
              ],
            ),
            SizedBox(height: 12),
            Text(
              '提示：两个文件名通常相同、扩展名不同，来源于同一张 Live Photo。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('选择照片'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // ── 步骤 1：选择 JPEG ──
    final jpegPick = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg'],
    );
    if (jpegPick == null || jpegPick.files.isEmpty) return;
    if (!mounted) return;

    // 步骤1完成提示
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '✅ 已选照片：${jpegPick.files.first.name}\n请继续选择对应的视频文件',
                  style: const TextStyle(height: 1.4),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );

    // ── 步骤 2：选择 MOV/MP4 ──
    final movPick = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: const ['mov', 'mp4'],
    );
    if (movPick == null || movPick.files.isEmpty) return;
    if (!mounted) return;

    // ── 步骤 3：上传（带 loading 弹窗） ──
    final session = _appState.session!;
    setState(() => _sending = true);
    _showUploadProgressDialog('正在处理 Live Photo…');
    try {
      final uploaded = await _appState.files.uploadLivePhoto(
        jpeg: jpegPick.files.first,
        mov: movPick.files.first,
        userId: session.userId,
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // 关 loading
      await _sendForDynamic(uploaded, session.userId);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // 关 loading
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('上传失败：${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 上传进度弹窗
  void _showUploadProgressDialog(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadMotionPhoto() async {
    final pick = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg'],
    );
    if (pick == null || pick.files.isEmpty) return;
    if (!mounted) return;
    final session = _appState.session!;
    setState(() => _sending = true);
    try {
      final uploaded = await _appState.files.uploadMotionPhoto(file: pick.files.first, userId: session.userId);
      await _sendForDynamic(uploaded, session.userId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendForDynamic(FileUploadResponse uploaded, int myId) async {
    final coverId = uploaded.coverId;
    final videoId = uploaded.videoId;
    if (coverId == null || videoId == null) {
      throw Exception('Upload response missing coverId/videoId');
    }

    final mid = await _appState.messages.sendDynamicPhoto(
      senderId: myId,
      receiverId: widget.peerId,
      coverId: coverId,
      videoId: videoId,
    );
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
    _appState.recordLocalMessage(msg);
    _scrollToBottom();
  }

  String _resolveUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '${_appState.apiBaseUrl}$trimmed';
    }
    return '${_appState.apiBaseUrl}/$trimmed';
  }

  void _openPlayer(String url) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(url: _resolveUrl(url))));
  }

  Future<void> _showAttachMenu() async {
    if (_sending) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    '发送媒体文件',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(ctx).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.image_outlined,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                  ),
                  title: const Text('图片 / 视频'),
                  subtitle: const Text('发送普通照片或视频文件'),
                  onTap: () => Navigator.of(ctx).pop('normal'),
                ),
                const Divider(indent: 72, height: 1),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(ctx).colorScheme.secondaryContainer,
                    child: Icon(
                      Icons.motion_photos_on_outlined,
                      color: Theme.of(ctx).colorScheme.secondary,
                    ),
                  ),
                  title: const Text('iOS Live Photo'),
                  subtitle: const Text('需分别选择 JPEG 和 MOV 两个文件'),
                  onTap: () => Navigator.of(ctx).pop('live'),
                ),
                const Divider(indent: 72, height: 1),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(ctx).colorScheme.tertiaryContainer,
                    child: Icon(
                      Icons.motion_photos_auto_outlined,
                      color: Theme.of(ctx).colorScheme.tertiary,
                    ),
                  ),
                  title: const Text('Android Motion Photo'),
                  subtitle: const Text('选择包含内嵌视频的 JPEG 文件'),
                  onTap: () => Navigator.of(ctx).pop('motion'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (action == null) return;
    if (action == 'normal') return _pickAndUploadNormal();
    if (action == 'live') return _pickAndUploadLivePhoto();
    if (action == 'motion') return _pickAndUploadMotionPhoto();
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.watch<AppState>().session!.userId;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                '${widget.peerId}',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('用户 ${widget.peerId}'),
          ],
        ),
        actions: [
          if (_sending)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, idx) {
                      final m = _messages[idx];
                      final isMine = m.senderId == myId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: MessageBubble(
                          message: m,
                          isMine: isMine,
                          onPlayVideo: _openPlayer,
                          resolveUrl: _resolveUrl,
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
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
                            isDense: true,
                          ),
                          minLines: 1,
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _sending ? null : _sendText,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _sending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('发送'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
