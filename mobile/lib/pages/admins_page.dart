import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/ui.dart';

/// 多管理员账号管理（仅超级管理员可用）。
class AdminsPage extends StatefulWidget {
  const AdminsPage({super.key});

  @override
  State<AdminsPage> createState() => _AdminsPageState();
}

class _AdminsPageState extends State<AdminsPage> {
  List<Admin> _admins = [];
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
      final a = await api.admins();
      if (!mounted) return;
      setState(() {
        _admins = a;
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

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _delete(Admin a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除管理员'),
        content: Text('确认删除账号「${a.username}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.rose600),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await (await ApiClient.fromStore()).deleteAdmin(a.id);
      bumpRefresh();
      await _load();
      _toast('已删除');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  Future<void> _toggleActive(Admin a) async {
    try {
      await (await ApiClient.fromStore())
          .updateAdmin(a.id, {'is_active': !a.isActive});
      await _load();
    } catch (e) {
      _toast('操作失败：$e');
    }
  }

  Future<void> _resetPassword(Admin a) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('重置「${a.username}」密码'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(hintText: '输入新密码'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定')),
        ],
      ),
    );
    final pwd = ctrl.text;
    ctrl.dispose();
    if (ok != true || pwd.isEmpty) return;
    try {
      await (await ApiClient.fromStore()).updateAdmin(a.id, {'password': pwd});
      _toast('已重置密码');
    } catch (e) {
      _toast('操作失败：$e');
    }
  }

  Future<void> _add() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AdminEditor(),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理员账号')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ink900,
        foregroundColor: Colors.white,
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('新增管理员'),
      ),
      body: RefreshIndicator(
        color: AppColors.ink900,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.ink900))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (_error != null) ErrorBanner(_error!),
                  ...List.generate(
                    _admins.length,
                    (i) => FadeSlideIn(
                      delay: Duration(milliseconds: 40 + i * 30),
                      child: _card(_admins[i]),
                    ),
                  ),
                  if (_admins.isEmpty && _error == null)
                    const EmptyState(
                        icon: Icons.group_outlined, text: '暂无管理员账号'),
                ],
              ),
      ),
    );
  }

  Widget _card(Admin a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                  color: a.isSuper ? AppColors.ink900 : AppColors.ink100,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(
                  a.isSuper ? Icons.shield : Icons.person_outline,
                  color: a.isSuper ? Colors.white : AppColors.ink600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(a.username,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink900)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: a.isSuper
                              ? AppColors.accent50
                              : AppColors.ink100,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(a.roleLabel,
                          style: TextStyle(
                              fontSize: 11,
                              color: a.isSuper
                                  ? AppColors.accent600
                                  : AppColors.ink500)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(a.isActive ? '启用中' : '已停用',
                      style: TextStyle(
                          fontSize: 12,
                          color: a.isActive
                              ? AppColors.emerald600
                              : AppColors.ink400)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.ink500),
              onSelected: (v) {
                switch (v) {
                  case 'pwd':
                    _resetPassword(a);
                  case 'toggle':
                    _toggleActive(a);
                  case 'delete':
                    _delete(a);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'pwd', child: Text('重置密码')),
                PopupMenuItem(
                    value: 'toggle', child: Text(a.isActive ? '停用' : '启用')),
                if (!a.isSuper)
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminEditor extends StatefulWidget {
  const _AdminEditor();

  @override
  State<_AdminEditor> createState() => _AdminEditorState();
}

class _AdminEditorState extends State<_AdminEditor> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String _role = 'staff';
  bool _saving = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写用户名和密码')));
      return;
    }
    setState(() => _saving = true);
    try {
      await (await ApiClient.fromStore())
          .createAdmin(_username.text.trim(), _password.text, _role);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.ink50,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                    color: AppColors.ink300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Row(children: [
              const Text('新增管理员',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink900)),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 6),
            TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: '用户名')),
            const SizedBox(height: 12),
            TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码')),
            const SizedBox(height: 14),
            Row(children: [
              _roleChip('staff', '普通管理员'),
              const SizedBox(width: 8),
              _roleChip('super', '超级管理员'),
            ]),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('创建'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleChip(String value, String label) {
    final active = _role == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _role = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.ink900 : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: active ? AppColors.ink900 : AppColors.ink200),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.ink600)),
        ),
      ),
    );
  }
}
