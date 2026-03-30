import 'package:dynamic_photo_chat_flutter/services/api_client.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _loginUserCtrl = TextEditingController();
  final TextEditingController _loginPassCtrl = TextEditingController();
  final TextEditingController _regUserCtrl = TextEditingController();
  final TextEditingController _regPassCtrl = TextEditingController();
  bool _loading = false;
  bool _loginObscure = true;
  bool _registerObscure = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginUserCtrl.dispose();
    _loginPassCtrl.dispose();
    _regUserCtrl.dispose();
    _regPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    final username = _loginUserCtrl.text.trim();
    final password = _loginPassCtrl.text;
    final validation = _validateLogin(username, password);
    if (validation != null) {
      _showSnack(validation);
      return;
    }

    setState(() => _loading = true);
    try {
      await context.read<AppState>().login(username, password);
    } catch (e) {
      _showSnack(_normalizeAuthError(e, isLogin: true));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _doRegister() async {
    final username = _regUserCtrl.text.trim();
    final password = _regPassCtrl.text;
    final validation = _validateRegister(username, password);
    if (validation != null) {
      _showSnack(validation);
      return;
    }

    setState(() => _loading = true);
    try {
      await context.read<AppState>().register(username, password);
    } catch (e) {
      _showSnack(_normalizeAuthError(e, isLogin: false));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String? _validateLogin(String username, String password) {
    if (username.isEmpty) return '请输入用户名';
    if (password.isEmpty) return '请输入密码';
    if (password.length < 6) return '密码至少需要 6 位';
    return null;
  }

  String? _validateRegister(String username, String password) {
    if (username.isEmpty) return '请输入用户名';
    if (username.length < 2) return '用户名至少需要 2 个字符';
    if (password.isEmpty) return '请输入密码';
    if (password.length < 6) return '密码至少需要 6 位';
    if (password.length > 32) return '密码长度不能超过 32 位';
    if (username.length > 24) return '用户名长度不能超过 24 个字符';
    return null;
  }

  String _normalizeAuthError(Object error, {required bool isLogin}) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final lower = raw.toLowerCase();
    if (isLogin) {
      if (lower.contains('login failed')) return '用户名或密码错误';
      if (lower.contains('user not found')) return '用户不存在，请先注册';
      if (lower.contains('password')) return '密码错误，请重新输入';
    } else {
      if (lower.contains('register failed')) return '注册失败，请稍后重试';
      if (lower.contains('exist')) return '该用户名已被注册';
      if (lower.contains('duplicate')) return '该用户名已被注册';
    }
    if (lower.contains('timeout')) return '请求超时，请检查网络连接';
    if (lower.contains('connection')) return '连接失败，请检查 API 地址和网络';
    return raw.isEmpty ? (isLogin ? '登录失败，请稍后重试' : '注册失败，请稍后重试') : raw;
  }

  Future<void> _editApiBaseUrl() async {
    final state = context.read<AppState>();
    final controller = TextEditingController(text: state.apiBaseUrl);
    final messenger = ScaffoldMessenger.of(context);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API 地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'API 基础地址',
            hintText: 'http://192.168.x.x:8080',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('请输入 API 地址')),
                );
                return;
              }
              try {
                final client = ApiClient(baseUrl: value);
                await client.get<List<Object?>>(
                  '/api/user/search',
                  query: const {'keyword': 'test'},
                  decode: (raw) => (raw as List?)?.cast<Object?>() ?? const [],
                );
                if (!ctx.mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('API 连接测试成功')),
                );
              } catch (_) {
                if (!ctx.mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('API 连接测试失败')),
                );
              }
            },
            child: const Text('测试'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    try {
      await context.read<AppState>().updateEndpoints(apiBaseUrl: value);
      _showSnack('API 地址已更新');
    } catch (e) {
      _showSnack(_normalizeAuthError(e, isLogin: true));
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apiBaseUrl = context.watch<AppState>().apiBaseUrl;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: _loading ? null : _editApiBaseUrl,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 26,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Vox',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '用图片、视频和 Live Photo 记录每一次聊天瞬间。',
                    style: TextStyle(color: Colors.grey.shade600, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      'API：$apiBaseUrl',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xFF2563EB),
                      labelStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      tabs: const [
                        Tab(text: '登录'),
                        Tab(text: '注册'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 310,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _AuthForm(
                          usernameController: _loginUserCtrl,
                          passwordController: _loginPassCtrl,
                          submitText: '登录',
                          loading: _loading,
                          obscureText: _loginObscure,
                          onToggleObscure: () => setState(() {
                            _loginObscure = !_loginObscure;
                          }),
                          onSubmit: _doLogin,
                        ),
                        _AuthForm(
                          usernameController: _regUserCtrl,
                          passwordController: _regPassCtrl,
                          submitText: '创建账号',
                          loading: _loading,
                          obscureText: _registerObscure,
                          onToggleObscure: () => setState(() {
                            _registerObscure = !_registerObscure;
                          }),
                          onSubmit: _doRegister,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    required this.usernameController,
    required this.passwordController,
    required this.submitText,
    required this.onSubmit,
    required this.loading,
    required this.obscureText,
    required this.onToggleObscure,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final String submitText;
  final VoidCallback onSubmit;
  final bool loading;
  final bool obscureText;
  final VoidCallback onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: usernameController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '用户名',
            hintText: '请输入用户名',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: passwordController,
          obscureText: obscureText,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            labelText: '密码',
            hintText: '请输入密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              onPressed: onToggleObscure,
              icon: Icon(
                obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '密码至少 6 位，建议使用字母和数字组合。',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: loading ? null : onSubmit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(submitText),
          ),
        ),
      ],
    );
  }
}
