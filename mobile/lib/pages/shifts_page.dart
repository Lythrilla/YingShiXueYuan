import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/ui.dart';

/// 排班管理：星期 + 时段 + 资源 + 负责人（开门人）。
class ShiftsPage extends StatefulWidget {
  const ShiftsPage({super.key});

  @override
  State<ShiftsPage> createState() => _ShiftsPageState();
}

class _ShiftsPageState extends State<ShiftsPage> {
  List<DutyShift> _shifts = [];
  List<Resource> _resources = [];
  List<Slot> _slots = [];
  List<String> _admins = [];
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
      final results = await Future.wait([
        api.shifts(),
        api.resources(),
        api.slots(),
      ]);
      List<String> admins = [];
      try {
        admins = (await api.admins()).map((a) => a.username).toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _shifts = results[0] as List<DutyShift>;
        _resources = results[1] as List<Resource>;
        _slots = results[2] as List<Slot>;
        _admins = admins;
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

  String _resourceName(int id) {
    if (id == 0) return '全部资源';
    return _resources
        .firstWhere((r) => r.id == id,
            orElse: () => Resource(
                id: 0,
                name: '已删除资源',
                kind: 'lab',
                description: '',
                imageUrl: '',
                totalQuantity: 0,
                individualBookable: false,
                sortOrder: 0,
                isActive: false,
                manager: ''))
        .name;
  }

  String _slotName(int id) {
    if (id == 0) return '全部时段';
    return _slots
        .firstWhere((s) => s.id == id,
            orElse: () => Slot(
                id: 0,
                name: '已删除时段',
                startTime: '',
                endTime: '',
                sortOrder: 0,
                isActive: false))
        .name;
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _delete(DutyShift s) async {
    try {
      await (await ApiClient.fromStore()).deleteShift(s.id);
      bumpRefresh();
      await _load();
      _toast('已删除排班');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  Future<void> _add() async {
    if (_admins.isEmpty) {
      _toast('需要超级管理员权限来读取负责人列表');
      return;
    }
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShiftEditor(
        resources: _resources,
        slots: _slots,
        admins: _admins,
      ),
    );
    if (changed == true) {
      bumpRefresh();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('排班 · 开门负责人')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ink900,
        foregroundColor: Colors.white,
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('新增排班'),
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
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.ink100,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Text(
                      '到点提醒去开门时，按「排班命中 > 资源默认负责人 > 全体管理员」的顺序确定通知谁。星期/时段/资源可设为「全部」做通配。',
                      style: TextStyle(fontSize: 12, color: AppColors.ink500),
                    ),
                  ),
                  ...List.generate(
                    _shifts.length,
                    (i) => FadeSlideIn(
                      delay: Duration(milliseconds: 40 + i * 30),
                      child: _card(_shifts[i]),
                    ),
                  ),
                  if (_shifts.isEmpty)
                    const EmptyState(
                        icon: Icons.calendar_month_outlined,
                        text: '还没有排班，去开门将通知资源负责人或全体管理员'),
                ],
              ),
      ),
    );
  }

  Widget _card(DutyShift s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: AppColors.ink900,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(weekdayLabel(s.weekday),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_resourceName(s.resourceId)} · ${_slotName(s.slotId)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink900)),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.badge_outlined,
                        size: 14, color: AppColors.ink400),
                    const SizedBox(width: 4),
                    Text(s.adminUsername,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.ink500)),
                  ]),
                ],
              ),
            ),
            IconButton(
                onPressed: () => _delete(s),
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppColors.rose600)),
          ],
        ),
      ),
    );
  }
}

class _ShiftEditor extends StatefulWidget {
  const _ShiftEditor({
    required this.resources,
    required this.slots,
    required this.admins,
  });
  final List<Resource> resources;
  final List<Slot> slots;
  final List<String> admins;

  @override
  State<_ShiftEditor> createState() => _ShiftEditorState();
}

class _ShiftEditorState extends State<_ShiftEditor> {
  int _weekday = -1;
  int _slotId = 0;
  int _resourceId = 0;
  late String _admin;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _admin = widget.admins.isNotEmpty ? widget.admins.first : '';
  }

  Future<void> _save() async {
    if (_admin.isEmpty) return;
    setState(() => _saving = true);
    try {
      await (await ApiClient.fromStore()).createShift(
        weekday: _weekday,
        slotId: _slotId,
        resourceId: _resourceId,
        adminUsername: _admin,
      );
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
              const Text('新增排班',
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
            _dropdown<int>(
              label: '星期',
              value: _weekday,
              items: const {
                -1: '每天',
                1: '周一',
                2: '周二',
                3: '周三',
                4: '周四',
                5: '周五',
                6: '周六',
                0: '周日',
              },
              onChanged: (v) => setState(() => _weekday = v),
            ),
            const SizedBox(height: 12),
            _dropdown<int>(
              label: '资源',
              value: _resourceId,
              items: {
                0: '全部资源',
                for (final r in widget.resources) r.id: r.name,
              },
              onChanged: (v) => setState(() => _resourceId = v),
            ),
            const SizedBox(height: 12),
            _dropdown<int>(
              label: '时段',
              value: _slotId,
              items: {
                0: '全部时段',
                for (final s in widget.slots) s.id: '${s.name} ${s.range}',
              },
              onChanged: (v) => setState(() => _slotId = v),
            ),
            const SizedBox(height: 12),
            _dropdown<String>(
              label: '负责人（开门人）',
              value: _admin,
              items: {for (final a in widget.admins) a: a},
              onChanged: (v) => setState(() => _admin = v),
            ),
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
                    : const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.ink200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isExpanded: true,
              value: value,
              items: items.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
