import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/ui.dart';

/// 实验室 / 设备管理：增删改、图片上传、默认负责人、上下架。
class ResourcesPage extends StatefulWidget {
  const ResourcesPage({super.key});

  @override
  State<ResourcesPage> createState() => _ResourcesPageState();
}

class _ResourcesPageState extends State<ResourcesPage> {
  List<Resource> _resources = [];
  List<String> _adminUsernames = [];
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
      final r = await api.resources();
      // 负责人候选（仅超级管理员可读，失败则忽略）。
      List<String> admins = [];
      try {
        admins = (await api.admins()).map((a) => a.username).toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _resources = r;
        _adminUsernames = admins;
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

  Future<void> _delete(Resource r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除资源'),
        content: Text('确认删除「${r.name}」？该操作不可恢复。'),
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
      await (await ApiClient.fromStore()).deleteResource(r.id);
      bumpRefresh();
      await _load();
      _toast('已删除');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _openEditor([Resource? r]) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResourceEditor(
        resource: r,
        adminUsernames: _adminUsernames,
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
      appBar: AppBar(title: const Text('实验室 / 设备')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ink900,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增资源'),
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
                    _resources.length,
                    (i) => FadeSlideIn(
                      delay: Duration(milliseconds: 40 + i * 40),
                      child: _card(_resources[i]),
                    ),
                  ),
                  if (_resources.isEmpty)
                    const EmptyState(
                        icon: Icons.meeting_room_outlined, text: '还没有资源'),
                ],
              ),
      ),
    );
  }

  Widget _card(Resource r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: _thumb(r),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(r.name,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink900)),
                      ),
                      _tag(r.kindLabel, AppColors.ink100, AppColors.ink600),
                      const SizedBox(width: 6),
                      r.isActive
                          ? _tag('已上架', AppColors.emerald50, AppColors.emerald700)
                          : _tag('已下架', AppColors.ink100, AppColors.ink400),
                    ],
                  ),
                  if (r.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(r.description,
                        style:
                            const TextStyle(fontSize: 13, color: AppColors.ink500)),
                  ],
                  const SizedBox(height: 10),
                  InfoRow(Icons.inventory_2_outlined, '总量 ${r.totalQuantity} · ${r.individualBookable ? '可个人预约' : '不可个人预约'}'),
                  InfoRow(Icons.badge_outlined,
                      '默认负责人：${r.manager.isEmpty ? '未指定' : r.manager}'),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openEditor(r),
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('编辑'),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => _delete(r),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.rose600,
                          side: const BorderSide(color: AppColors.rose200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: const Icon(Icons.delete_outline, size: 19),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(Resource r) {
    if (r.imageUrl.isEmpty) {
      return Container(
        color: AppColors.ink100,
        child: Icon(
            r.kind == 'equipment'
                ? Icons.tune
                : Icons.meeting_room_outlined,
            size: 36,
            color: AppColors.ink300),
      );
    }
    return FutureBuilder<ApiClient>(
      future: ApiClient.fromStore(),
      builder: (ctx, snap) {
        final url = snap.hasData ? snap.data!.absoluteUrl(r.imageUrl) : '';
        if (url.isEmpty) return Container(color: AppColors.ink100);
        return Image.network(url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(
                color: AppColors.ink100,
                child: const Icon(Icons.broken_image_outlined,
                    color: AppColors.ink300)));
      },
    );
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
      );
}

/// 资源新增 / 编辑底部表单。
class _ResourceEditor extends StatefulWidget {
  const _ResourceEditor({this.resource, required this.adminUsernames});
  final Resource? resource;
  final List<String> adminUsernames;

  @override
  State<_ResourceEditor> createState() => _ResourceEditorState();
}

class _ResourceEditorState extends State<_ResourceEditor> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _qty;
  late String _kind;
  late bool _individual;
  late bool _active;
  late String _imageUrl;
  late String _manager;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final r = widget.resource;
    _name = TextEditingController(text: r?.name ?? '');
    _desc = TextEditingController(text: r?.description ?? '');
    _qty = TextEditingController(text: (r?.totalQuantity ?? 1).toString());
    _kind = r?.kind ?? 'lab';
    _individual = r?.individualBookable ?? true;
    _active = r?.isActive ?? true;
    _imageUrl = r?.imageUrl ?? '';
    _manager = r?.manager ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      setState(() => _uploading = true);
      final bytes = await picked.readAsBytes();
      final api = await ApiClient.fromStore();
      final url = await api.uploadImage(bytes, picked.name);
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('上传失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写资源名称')));
      return;
    }
    setState(() => _saving = true);
    final body = {
      'name': _name.text.trim(),
      'kind': _kind,
      'description': _desc.text.trim(),
      'image_url': _imageUrl,
      'total_quantity': int.tryParse(_qty.text.trim()) ?? 1,
      'individual_bookable': _individual,
      'is_active': _active,
      'manager': _manager,
    };
    try {
      final api = await ApiClient.fromStore();
      if (widget.resource == null) {
        await api.createResource(body);
      } else {
        await api.updateResource(widget.resource!.id, body);
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
    final managers = <String>{'', ..._validManagerOptions()}.toList();
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: const BoxDecoration(
          color: AppColors.ink50,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                    color: AppColors.ink300,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Text(widget.resource == null ? '新增资源' : '编辑资源',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink900)),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close)),
              ]),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _imagePicker(),
                  const SizedBox(height: 14),
                  _label('名称'),
                  TextField(
                      controller: _name,
                      decoration:
                          const InputDecoration(hintText: '如 全景声棚')),
                  const SizedBox(height: 14),
                  _label('类型'),
                  Row(children: [
                    _kindChip('lab', '实验室'),
                    const SizedBox(width: 8),
                    _kindChip('equipment', '设备'),
                  ]),
                  const SizedBox(height: 14),
                  _label('描述'),
                  TextField(
                      controller: _desc,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(hintText: '简要说明（选填）')),
                  const SizedBox(height: 14),
                  _label('总数量'),
                  TextField(
                      controller: _qty,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '1')),
                  const SizedBox(height: 14),
                  _label('默认负责人（开门人）'),
                  _managerField(managers),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _individual,
                    onChanged: (v) => setState(() => _individual = v),
                    activeTrackColor: AppColors.ink900,
                    title: const Text('允许学生个人预约',
                        style: TextStyle(fontSize: 14)),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    activeTrackColor: AppColors.ink900,
                    title: const Text('上架（可被预约）',
                        style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(height: 12),
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
          ],
        ),
      ),
    );
  }

  List<String> _validManagerOptions() {
    final opts = [...widget.adminUsernames];
    if (_manager.isNotEmpty && !opts.contains(_manager)) opts.add(_manager);
    return opts;
  }

  Widget _managerField(List<String> managers) {
    if (widget.adminUsernames.isEmpty && _manager.isEmpty) {
      // 无法读取管理员列表（非超管）→ 退化为文本输入。
      return TextField(
        controller: TextEditingController(text: _manager),
        onChanged: (v) => _manager = v.trim(),
        decoration: const InputDecoration(hintText: '填管理员用户名，留空=不指定'),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ink200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _manager,
          items: managers
              .map((u) => DropdownMenuItem(
                  value: u, child: Text(u.isEmpty ? '不指定' : u)))
              .toList(),
          onChanged: (v) => setState(() => _manager = v ?? ''),
        ),
      ),
    );
  }

  Widget _imagePicker() {
    return GestureDetector(
      onTap: _uploading ? null : _pickImage,
      child: Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ink200),
        ),
        clipBehavior: Clip.antiAlias,
        child: _uploading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.ink900))
            : _imageUrl.isEmpty
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 32, color: AppColors.ink400),
                      SizedBox(height: 6),
                      Text('点击上传图片',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.ink400)),
                    ],
                  )
                : FutureBuilder<ApiClient>(
                    future: ApiClient.fromStore(),
                    builder: (ctx, snap) {
                      final url = snap.hasData
                          ? snap.data!.absoluteUrl(_imageUrl)
                          : '';
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (url.isNotEmpty)
                            Image.network(url, fit: BoxFit.cover),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(20)),
                              child: const Text('更换',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.ink600)),
      );

  Widget _kindChip(String value, String label) {
    final active = _kind == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _kind = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.ink900 : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? AppColors.ink900 : AppColors.ink200),
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
