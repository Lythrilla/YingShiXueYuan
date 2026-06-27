import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/ui.dart';

/// 操作日志：审批 / 取消 / 增删改等动作的审计记录。
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<OperationLog> _logs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = await ApiClient.fromStore();
      final l = await api.logs(limit: 200);
      if (!mounted) return;
      setState(() {
        _logs = l;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '无法连接服务器';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('操作日志')),
      body: RefreshIndicator(
        color: AppColors.ink900,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.ink900))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error != null) ErrorBanner(_error!),
                  ...List.generate(
                    _logs.length,
                    (i) => FadeSlideIn(
                      delay: Duration(milliseconds: 30 + i * 20),
                      child: _card(_logs[i]),
                    ),
                  ),
                  if (_logs.isEmpty && _error == null)
                    const EmptyState(
                        icon: Icons.history, text: '暂无操作日志'),
                ],
              ),
      ),
    );
  }

  Widget _card(OperationLog l) {
    final (IconData icon, Color color) = switch (l.action) {
      'verify' => (Icons.check_circle_outline, AppColors.emerald600),
      'cancel' => (Icons.cancel_outlined, AppColors.rose600),
      'create' => (Icons.add_circle_outline, AppColors.accent500),
      'update' => (Icons.edit_outlined, AppColors.ink600),
      'delete' => (Icons.delete_outline, AppColors.rose600),
      'login' => (Icons.login, AppColors.ink500),
      _ => (Icons.bolt_outlined, AppColors.ink500),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${l.actor} · ${_actionLabel(l.action)}${l.target.isNotEmpty ? ' · ${l.target}' : ''}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink900),
                        ),
                      ),
                      Text(_shortTime(l.createdAt),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.ink400)),
                    ],
                  ),
                  if (l.detail.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(l.detail,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.ink500)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _actionLabel(String a) => switch (a) {
        'verify' => '通过预约',
        'cancel' => '取消预约',
        'create' => '新增',
        'update' => '修改',
        'delete' => '删除',
        'login' => '登录',
        'batch_verify' => '批量通过',
        'batch_cancel' => '批量取消',
        _ => a,
      };

  String _shortTime(String iso) {
    if (iso.length >= 16) return iso.substring(5, 16).replaceFirst('T', ' ');
    return iso;
  }
}
