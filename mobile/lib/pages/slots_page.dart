import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/ui.dart';

/// 时间段管理：增删改、上下架。
class SlotsPage extends StatefulWidget {
  const SlotsPage({super.key});

  @override
  State<SlotsPage> createState() => _SlotsPageState();
}

class _SlotsPageState extends State<SlotsPage> {
  List<Slot> _slots = [];
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
      final s = await api.slots();
      if (!mounted) return;
      setState(() {
        _slots = s;
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

  Future<void> _delete(Slot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除时间段'),
        content: Text('确认删除「${s.name} ${s.range}」？'),
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
      await (await ApiClient.fromStore()).deleteSlot(s.id);
      bumpRefresh();
      await _load();
      _toast('已删除');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  Future<void> _openEditor([Slot? s]) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SlotEditor(slot: s),
    );
    if (changed == true) {
      bumpRefresh();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('时间段')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ink900,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增时段'),
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
                    _slots.length,
                    (i) => FadeSlideIn(
                      delay: Duration(milliseconds: 40 + i * 40),
                      child: _card(_slots[i]),
                    ),
                  ),
                  if (_slots.isEmpty)
                    const EmptyState(
                        icon: Icons.schedule_outlined, text: '还没有时间段'),
                ],
              ),
      ),
    );
  }

  Widget _card(Slot s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                  color: AppColors.ink100,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.schedule, color: AppColors.ink600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(s.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink900)),
                    const SizedBox(width: 8),
                    if (!s.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.ink100,
                            borderRadius: BorderRadius.circular(20)),
                        child: const Text('已停用',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.ink400)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(s.range,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.ink500)),
                ],
              ),
            ),
            IconButton(
                onPressed: () => _openEditor(s),
                icon: const Icon(Icons.edit_outlined,
                    size: 20, color: AppColors.ink600)),
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

class _SlotEditor extends StatefulWidget {
  const _SlotEditor({this.slot});
  final Slot? slot;

  @override
  State<_SlotEditor> createState() => _SlotEditorState();
}

class _SlotEditorState extends State<_SlotEditor> {
  late final TextEditingController _name;
  late String _start;
  late String _end;
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.slot;
    _name = TextEditingController(text: s?.name ?? '');
    _start = s?.startTime ?? '08:00';
    _end = s?.endTime ?? '12:00';
    _active = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final parts = (isStart ? _start : _end).split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '8') ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final v =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() => isStart ? _start = v : _end = v);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写时段名称')));
      return;
    }
    setState(() => _saving = true);
    final body = {
      'name': _name.text.trim(),
      'start_time': _start,
      'end_time': _end,
      'is_active': _active,
    };
    try {
      final api = await ApiClient.fromStore();
      if (widget.slot == null) {
        await api.createSlot(body);
      } else {
        await api.updateSlot(widget.slot!.id, body);
      }
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
              Text(widget.slot == null ? '新增时段' : '编辑时段',
                  style: const TextStyle(
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
                controller: _name,
                decoration: const InputDecoration(
                    labelText: '名称', hintText: '如 上午 / 下午 / 晚上')),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _timeBox('开始', _start, () => _pickTime(true))),
              const SizedBox(width: 12),
              Expanded(child: _timeBox('结束', _end, () => _pickTime(false))),
            ]),
            const SizedBox(height: 4),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              activeTrackColor: AppColors.ink900,
              title: const Text('启用', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: 6),
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

  Widget _timeBox(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.ink200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.ink400)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink900)),
              ],
            ),
            const Icon(Icons.access_time, size: 18, color: AppColors.ink400),
          ],
        ),
      ),
    );
  }
}
