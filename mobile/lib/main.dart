import 'package:flutter/material.dart';

import 'background_service.dart';
import 'notification_service.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();
  await BackgroundPoller.configure();

  final token = await Store.token();
  runApp(YingShiAdminApp(loggedIn: token != null && token.isNotEmpty));
}

class YingShiAdminApp extends StatelessWidget {
  const YingShiAdminApp({super.key, required this.loggedIn});
  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '录音实验室 · 后台',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: loggedIn ? const HomePage() : const LoginPage(),
    );
  }
}
