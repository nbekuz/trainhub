import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/routes/route_names.dart';

/// Trainer course library: list / filter / edit / submit / assign.
class MyProgramsPage extends StatefulWidget {
  const MyProgramsPage({super.key});

  @override
  State<MyProgramsPage> createState() => _MyProgramsPageState();
}

class _MyProgramsPageState extends State<MyProgramsPage> {
  static const _filters = <(String?, String)>[
    (null, 'Все'),
    ('draft', 'Черновик'),
    ('published', 'Опубликовано'),
  ];

  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  String? _status;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await FitApi.trainerPrograms(status: _status);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = FitApi.messageOf(e);
      });
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((p) {
      final title = p['title']?.toString().toLowerCase() ?? '';
      final desc = p['description']?.toString().toLowerCase() ?? '';
      return title.contains(q) || desc.contains(q);
    }).toList();
  }

  Future<void> _create() async {
    final ok = await context.push<bool>(RouteNames.createProgram);
    if (ok == true && mounted) _load();
  }

  Future<void> _edit(Map<String, dynamic> program) async {
    final id = int.tryParse('${program['id']}') ?? 0;
    if (id == 0) return;
    final ok = await context.push<bool>(RouteNames.createProgram, extra: id);
    if (ok == true && mounted) _load();
  }

  Future<void> _submit(int id, {required bool resubmit}) async {
    try {
      await FitApi.submitProgram(id);
      if (!mounted) return;
      Toast.success('Программа опубликована');
      _load();
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    }
  }

  Future<void> _assign(Map<String, dynamic> program) async {
    final programId = int.tryParse('${program['id']}') ?? 0;
    if (programId == 0) return;
    List<FitClient> clients = const [];
    try {
      clients = await FitApi.trainerClients();
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
      return;
    }
    if (!mounted) return;
    if (clients.isEmpty) {
      Toast.info('Клиентов пока нет');
      return;
    }
    final picked = await showModalBottomSheet<({List<int> linkIds, String? note})>(
      context: context,
      backgroundColor: AppColors.fitCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AssignProgramSheet(clients: clients),
    );
    if (picked == null || picked.linkIds.isEmpty) return;
    try {
      await FitApi.assignProgram(programId, linkIds: picked.linkIds, note: picked.note);
      if (mounted) {
        final n = picked.linkIds.length;
        Toast.success(n == 1 ? 'Курс назначен клиенту' : 'Курс назначен $n клиентам');
      }
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    }
  }

  String get _emptyTitle => switch (_status) {
        'draft' => 'Нет черновиков',
        'published' => 'Нет опубликованных курсов',
        _ => 'Пока нет курсов',
      };

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          HubBackTitle(
            title: 'Мои курсы',
            trailing: IconButton(
              onPressed: _create,
              icon: const Icon(Icons.add_circle_outline, color: AppColors.accent),
            ),
          ),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              hintText: 'Поиск курса',
              hintStyle: const TextStyle(color: AppColors.fitGrey),
              prefixIcon: const Icon(Icons.search, color: AppColors.fitGrey),
              filled: true,
              fillColor: const Color(0xFF1C1C1C),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _filters[i];
                final selected = _status == f.$1;
                return ChoiceChip(
                  label: Text(f.$2),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) {
                    if (_status == f.$1) return;
                    setState(() => _status = f.$1);
                    _load();
                  },
                  selectedColor: AppColors.accent,
                  labelStyle: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  backgroundColor: const Color(0xFF232323),
                  side: BorderSide(color: selected ? AppColors.accent : const Color(0xFF3A3A3A)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.accent,
              onRefresh: _load,
              child: _loading
                  ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator(color: AppColors.accent))])
                  : _error != null
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.fitGrey)),
                            TextButton(onPressed: _load, child: const Text('Повторить', style: TextStyle(color: AppColors.accent))),
                          ],
                        )
                      : visible.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              children: [
                                const SizedBox(height: 72),
                                Text(_emptyTitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                const Text(
                                  'Создайте курс с неделями, днями и упражнениями из видеобиблиотеки',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.fitGrey, height: 1.35),
                                ),
                                const SizedBox(height: 20),
                                Center(
                                  child: FilledButton(
                                    onPressed: _create,
                                    style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                                    child: const Text('Создать курс', style: TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 40),
                              itemCount: visible.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final p = visible[i];
                                final id = int.tryParse('${p['id']}') ?? 0;
                                final status = p['status']?.toString() ?? '';
                                final level = p['level']?.toString() ?? '';
                                final weeks = p['duration_weeks'];
                                final meta = [
                                  if (level.isNotEmpty) level,
                                  if (weeks != null) '$weeks нед.',
                                ].join(' · ');
                                return Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1C1C1C),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF2E2E2E)),
                                  ),
                                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => _edit(p),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p['title']?.toString() ?? 'Курс',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                                              ),
                                              if (meta.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(meta, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                                              ],
                                              const SizedBox(height: 8),
                                              _ProgramStatusBadge(status: status),
                                            ],
                                          ),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        color: AppColors.fitCard,
                                        icon: const Icon(Icons.more_vert, color: Colors.white70),
                                        onSelected: (v) {
                                          switch (v) {
                                            case 'edit':
                                              _edit(p);
                                            case 'submit':
                                              _submit(id, resubmit: false);
                                            case 'assign':
                                              _assign(p);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                                          if (status != 'published' && status != 'archived')
                                            const PopupMenuItem(
                                              value: 'submit',
                                              child: Text('Опубликовать'),
                                            ),
                                          const PopupMenuItem(value: 'assign', child: Text('Назначить клиенту')),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgramStatusBadge extends StatelessWidget {
  const _ProgramStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      'draft' || 'pending_review' || 'rejected' => ('Черновик', const Color(0xFFB0B0B0), const Color(0xFF2A2A2A)),
      'published' => ('Опубликовано', AppColors.accent, AppColors.accent.withValues(alpha: 0.16)),
      'archived' => ('Архив', AppColors.fitGrey, const Color(0xFF2A2A2A)),
      _ => (status.isEmpty ? '—' : status, AppColors.fitGrey, const Color(0xFF2A2A2A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _AssignProgramSheet extends StatefulWidget {
  const _AssignProgramSheet({required this.clients});

  final List<FitClient> clients;

  @override
  State<_AssignProgramSheet> createState() => _AssignProgramSheetState();
}

class _AssignProgramSheetState extends State<_AssignProgramSheet> {
  final _noteCtrl = TextEditingController();
  final _selected = <int>{};

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clients = widget.clients;
    final maxH = MediaQuery.sizeOf(context).height * 0.72;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: maxH,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Назначить курс клиентам',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _noteCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Комментарий (необязательно)',
                  hintStyle: TextStyle(color: AppColors.fitGrey),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      if (_selected.length == clients.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(clients.map((c) => c.id));
                      }
                    }),
                    child: Text(
                      _selected.length == clients.length ? 'Снять всё' : 'Выбрать всех',
                      style: const TextStyle(color: AppColors.accent),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_selected.length} из ${clients.length}',
                    style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: clients.length,
                itemBuilder: (_, i) {
                  final c = clients[i];
                  final name = '${c.name} ${c.surname}'.trim();
                  final checked = _selected.contains(c.id);
                  return CheckboxListTile(
                    value: checked,
                    activeColor: AppColors.accent,
                    checkColor: Colors.black,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      name.isEmpty ? 'Клиент' : name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(c.id);
                      } else {
                        _selected.remove(c.id);
                      }
                    }),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                              context,
                              (
                                linkIds: _selected.toList(),
                                note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                              ),
                            ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: const Color(0xFF3A3A3A),
                    ),
                    child: Text(
                      _selected.isEmpty ? 'Выберите клиентов' : 'Назначить (${_selected.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
