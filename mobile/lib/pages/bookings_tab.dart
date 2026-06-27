import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../background_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/ui.dart';

/// 预约管理：状态/资源/日期/关键词筛选 + 批量审批 + 审批备注。
class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  List<Booking> _bookings = [];
  List<Resource> _resources = [];
  bool _loading = true;
  String? _error;

  String _status = 'booked'; // '' = 全部
  int _resourceId = 0;
  String _date = '';
  String _keyword = '';
  final _keywordCtrl = TextEditingController();

  bool _selecting = false;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadResources();
    _load();
    appRefresh.addListener(_onSignal);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_onSignal);
    _keywordCtrl.dispose();
    super.dispose();
  }

  void _onSignal() => _load();

  Future<void> _loadResources() async {
    try {
      final api = await ApiClient.fromStore();
      final r = await api.resources();
      if (mounted) setState(() => _resources = r);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final api = await ApiClient.fromStore();
      final list = await api.bookings(
        status: _status,
        resourceId: _resourceId,
        date: _date,
        keyword: _keyword,
      );
      if (!mounted) return;
      setState(() {
        _bookings = list;
        _loading = false;
        _error = null;
        _selected.removeWhere((id) => !list.any((b) => b.id == id));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '无法连接服务器';
        _loading = false;
      });
    }
  }

  Future<void> _verify(Booking b) async {
    final note = await _askNote('通过预约', '可填写审批备注（选填）');
    if (note == null) return;
    await _run(() async => (await ApiClient.fromStore()).verify(b.id, note: note),
        '已通过');
  }

  Future<void> _cancel(Booking b) async {
    final note = await _askNote('取消预约', '可填写取消原因（选填）',
        confirmText: '确认取消', danger: true);
    if (note == null) return;
    await _run(() async => (await ApiClient.fromStore()).cancel(b.id, note: note),
        '已取消');
  }

  Future<void> _batch(String op) async {
    if (_selected.isEmpty) return;
    final isVerify = op == 'verify';
    final note = await _askNote(
        isVerify ? '批量通过 ${_selected.length} 条' : '批量取消 ${_selected.length} 条',
        '可填写审批备注（选填）',
        confirmText: isVerify ? '通过' : '确认取消',
        danger: !isVerify);
    if (note == null) return;
    await _run(() async {
      final n =
          await (await ApiClient.fromStore()).batch(op, _selected.toList(), note: note);
      if (mounted) setState(() => _selected.clear());
      return n;
    }, isVerify ? '已批量通过' : '已批量取消');
  }

  Future<void> _run(Future<dynamic> Function() fn, String okMsg) async {
    try {
      await fn();
      BackgroundPoller.pollNow();
      bumpRefresh();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(okMsg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    }
  }

  /// 弹出备注输入框；返回 null 表示取消，返回字符串（可空）表示确认。
  Future<String?> _askNote(String title, String hint,
      {String confirmText = '确定', bool danger = false}) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger
                ? TextButton.styleFrom(foregroundColor: AppColors.rose600)
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    return ok == true ? text : null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() => _date =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _filterBar(),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.ink900,
            onRefresh: _load,
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.ink900))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      if (_error != null) ErrorBanner(_error!),
                      ...List.generate(
                        _bookings.length,
                        (i) => FadeSlideIn(
                          delay: Duration(milliseconds: 40 + i * 30),
                          child: _bookingCard(_bookings[i]),
                        ),
                      ),
                      if (_bookings.isEmpty)
                        const EmptyState(
                            icon: Icons.inbox_outlined, text: '没有符合条件的预约'),
                    ],
                  ),
          ),
        ),
        if (_selecting) _batchBar(),
      ],
    );
  }

  Widget _filterBar() {
    return Container(
      color: AppColors.ink50,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keywordCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '姓名 / 电话 / 指导教师',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _keyword.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _keywordCtrl.clear();
                              setState(() => _keyword = '');
                              _load();
                            },
                          ),
                  ),
                  onSubmitted: (v) {
                    setState(() => _keyword = v.trim());
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 8),
              _selectToggle(),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _statusDropdown(),
                const SizedBox(width: 8),
                _resourceDropdown(),
                const SizedBox(width: 8),
                _dateChip(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectToggle() {
    return TapScale(
      child: GestureDetector(
        onTap: () => setState(() {
          _selecting = !_selecting;
          if (!_selecting) _selected.clear();
        }),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _selecting ? AppColors.ink900 : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _selecting ? AppColors.ink900 : AppColors.ink200),
          ),
          child: Row(children: [
            Icon(Icons.checklist_rtl,
                size: 18,
                color: _selecting ? Colors.white : AppColors.ink600),
            const SizedBox(width: 6),
            Text('多选',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _selecting ? Colors.white : AppColors.ink600)),
          ]),
        ),
      ),
    );
  }

  Widget _chipShell({required Widget child}) => Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.ink200),
        ),
        child: child,
      );

  Widget _statusDropdown() {
    const options = <String, String>{
      'booked': '待处理',
      'verified': '已通过',
      'cancelled': '已取消',
      '': '全部状态',
    };
    return _chipShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _status,
          isDense: true,
          icon: const Icon(Icons.expand_more, size: 18),
          style: const TextStyle(fontSize: 13, color: AppColors.ink800),
          items: options.entries
              .map((e) =>
                  DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _status = v);
            _load();
          },
        ),
      ),
    );
  }

  Widget _resourceDropdown() {
    return _chipShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _resourceId,
          isDense: true,
          icon: const Icon(Icons.expand_more, size: 18),
          style: const TextStyle(fontSize: 13, color: AppColors.ink800),
          items: [
            const DropdownMenuItem(value: 0, child: Text('全部资源')),
            ..._resources.map(
                (r) => DropdownMenuItem(value: r.id, child: Text(r.name))),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _resourceId = v);
            _load();
          },
        ),
      ),
    );
  }

  Widget _dateChip() {
    return GestureDetector(
      onTap: _pickDate,
      child: _chipShell(
        child: Row(children: [
          const Icon(Icons.event_outlined, size: 16, color: AppColors.ink600),
          const SizedBox(width: 6),
          Text(_date.isEmpty ? '全部日期' : _date,
              style: const TextStyle(fontSize: 13, color: AppColors.ink800)),
          if (_date.isNotEmpty) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                setState(() => _date = '');
                _load();
              },
              child: const Icon(Icons.close, size: 14, color: AppColors.ink400),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _batchBar() {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Text('已选 ${_selected.length} 条',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink700)),
              const Spacer(),
              OutlinedButton(
                onPressed: _selected.isEmpty ? null : () => _batch('cancel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.rose600,
                  side: const BorderSide(color: AppColors.rose200),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('批量取消'),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _selected.isEmpty ? null : () => _batch('verify'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20)),
                child: const Text('批量通过'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookingCard(Booking b) {
    final selected = _selected.contains(b.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: _selecting
            ? () => setState(() {
                  if (selected) {
                    _selected.remove(b.id);
                  } else {
                    _selected.add(b.id);
                  }
                })
            : null,
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_selecting) ...[
                    Icon(
                      selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: selected ? AppColors.ink900 : AppColors.ink300,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.applicantName,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink900)),
                        const SizedBox(height: 2),
                        Text(b.phone,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.ink400)),
                      ],
                    ),
                  ),
                  StatusChip(b.status),
                ],
              ),
              const SizedBox(height: 14),
              InfoRow(Icons.meeting_room_outlined, b.resource.name),
              InfoRow(Icons.event_outlined,
                  '${b.date}  ${b.slot.name} ${b.slot.range}'),
              InfoRow(Icons.groups_outlined,
                  '${b.numPeople} 人 / ${b.quantity} 套${b.instructor.isNotEmpty ? '  ·  指导：${b.instructor}' : ''}'),
              if (b.description.isNotEmpty)
                InfoRow(Icons.notes_outlined, b.description),
              if (b.adminNote.isNotEmpty)
                InfoRow(Icons.sticky_note_2_outlined,
                    '备注：${b.adminNote}${b.processedBy.isNotEmpty ? '（${b.processedBy}）' : ''}'),
              if (!_selecting && b.status == 'booked') ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TapScale(
                      child: _actionButton(
                        label: '通过',
                        icon: Icons.check_circle_outline,
                        bg: AppColors.emerald50,
                        fg: AppColors.emerald700,
                        onTap: () => _verify(b),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TapScale(
                      child: _actionButton(
                        label: '取消',
                        icon: Icons.cancel_outlined,
                        bg: Colors.white,
                        fg: AppColors.rose600,
                        border: AppColors.rose200,
                        onTap: () => _cancel(b),
                      ),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color bg,
    required Color fg,
    Color? border,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border ?? bg),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      );
}
