import 'package:flutter/material.dart';

import '../api_client.dart';
import '../background_service.dart';
import '../native.dart';
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
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await ApiClient.fromStore();
      final res = await api.login(_username.text.trim(), _password.text);
      await Store.setToken(res.token);
      await Store.setUsername(res.username);
      await Store.setRole(res.role);
      await Native.syncNativeAlertPoller(token: res.token);
      await BackgroundPoller.start();
      BackgroundPoller.reconnect();
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
      backgroundColor: AppColors.ink50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: FadeSlideIn(
              offset: 24,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.ink200),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F18181B),
                      blurRadius: 28,
                      offset: Offset(0, 12),
                      spreadRadius: -12,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandMark(size: 46, radius: 16),
                    const SizedBox(height: 20),
                    const Text('录音系预约后台',
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            color: AppColors.ink900)),
                    const SizedBox(height: 4),
                    const Text('河北科技大学影视学院录音系',
                        style: TextStyle(fontSize: 13, color: AppColors.ink400)),
                    const SizedBox(height: 28),
                    _field('用户名', _username),
                    const SizedBox(height: 16),
                    _field('密码', _password, obscure: true, hint: '请输入密码'),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.rose50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.rose200),
                        ),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.rose600, fontSize: 13)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: TapScale(
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
                    ),
                  ],
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
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink600)),
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
