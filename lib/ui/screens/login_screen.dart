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
  final _loginUserCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  final _regUserCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  bool _loading = false;

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
    if (username.isEmpty || password.isEmpty) return;
    setState(() => _loading = true);
    try {
      await context.read<AppState>().login(username, password);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doRegister() async {
    final username = _regUserCtrl.text.trim();
    final password = _regPassCtrl.text;
    if (username.isEmpty || password.isEmpty) return;
    setState(() => _loading = true);
    try {
      await context.read<AppState>().register(username, password);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editApiBaseUrl() async {
    final state = context.read<AppState>();
    final controller = TextEditingController(text: state.apiBaseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('设置API地址'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              hintText: 'http://192.168.x.x:8082 或 http://127.0.0.1:8082',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消')),
            TextButton(
              onPressed: () async {
                final url = controller.text.trim();
                final ok = await state.testApiConnection(url);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? '连接成功' : '连接失败')),
                );
              },
              child: const Text('测试'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (value == null || value.isEmpty) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().updateEndpoints(apiBaseUrl: value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = context.watch<AppState>().apiBaseUrl;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dynamic Photo Chat'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _editApiBaseUrl,
            icon: const Icon(Icons.settings),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '登录'),
            Tab(text: '注册'),
          ],
        ),
      ),
      body: AbsorbPointer(
        absorbing: _loading,
        child: TabBarView(
          controller: _tabController,
          children: [
            _AuthForm(
              usernameController: _loginUserCtrl,
              passwordController: _loginPassCtrl,
              submitText: '登录',
              onSubmit: _doLogin,
              loading: _loading,
              apiBaseUrl: baseUrl,
            ),
            _AuthForm(
              usernameController: _regUserCtrl,
              passwordController: _regPassCtrl,
              submitText: '注册并登录',
              onSubmit: _doRegister,
              loading: _loading,
              apiBaseUrl: baseUrl,
            ),
          ],
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
    required this.apiBaseUrl,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final String submitText;
  final VoidCallback onSubmit;
  final bool loading;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'API: $apiBaseUrl',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: usernameController,
            decoration: const InputDecoration(labelText: '用户名'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            decoration: const InputDecoration(labelText: '密码'),
            obscureText: true,
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSubmit,
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(submitText),
            ),
          ),
        ],
      ),
    );
  }
}
