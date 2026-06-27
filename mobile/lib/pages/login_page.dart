import 'package:flutter/material.dart';

import '../api_client.dart';
import '../background_service.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _server = TextEditingController();
  bool _loading = false;
  bool _showServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Store.serverUrl().then((v) => _server.text = v);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Store.setServerUrl(_server.text);
      final api = await ApiClient.fromStore();
      final res = await api.login(_username.text.trim(), _password.text);
      await Store.setToken(res.token);
      await Store.setUsername(res.username);
      await BackgroundPoller.start();
      BackgroundPoller.pollNow();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(fadeThroughRoute(const HomePage()));
    } on ApiException catch (e) {
      setState(() => _error = e.isUnauthorized ? '用户名或密码错误' : e.message);
    } catch (e) {
      setState(() => _error = '无法连接服务器，请检查网络或服务器地址');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brand700, AppColors.brand600, AppColors.brand500],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeSlideIn(
                offset: 28,
                child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, 20)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 56,
                      width: 56,
                      decoration: BoxDecoration(
                        color: AppColors.brand50,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      alignment: Alignment.center,
                      child: const Text('🎙️', style: TextStyle(fontSize: 26)),
                    ),
                    const SizedBox(height: 16),
                    const Text('预约系统后台',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.slate800)),
                    const SizedBox(height: 4),
                    const Text('录音实验室管理控制台',
                        style: TextStyle(fontSize: 13, color: AppColors.slate400)),
                    const SizedBox(height: 24),
                    _field('用户名', _username),
                    const SizedBox(height: 14),
                    _field('密码', _password, obscure: true, hint: '请输入密码'),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _showServer = !_showServer),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        child: Text(_showServer ? '收起服务器设置' : '服务器设置',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.brand500)),
                      ),
                    ),
                    if (_showServer) ...[
                      const SizedBox(height: 4),
                      _field('服务器地址', _server, hint: 'http://117.72.222.31:8888'),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.rose50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_error!,
                            style: const TextStyle(color: AppColors.rose, fontSize: 13)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('登 录'),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {bool obscure = false, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate600)),
        ),
        TextField(
          controller: c,
          obscureText: obscure,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}
