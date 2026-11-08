import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/ru_phone.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  late final TextEditingController _name;
  late final TextEditingController _surname;
  late final TextEditingController _phone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _telegram;
  late final TextEditingController _email;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(fitSessionProvider).user;
    _name = TextEditingController(text: user?.name ?? '');
    _surname = TextEditingController(text: user?.surname ?? '');
    final phone = (user?.phone ?? '').trim();
    _phone = TextEditingController(text: phone.isEmpty ? '' : RuPhone.formatDisplay(phone));
    final wa = (user?.whatsapp ?? '').trim();
    _whatsapp = TextEditingController(text: wa.isEmpty ? '' : RuPhone.formatDisplay(wa));
    _telegram = TextEditingController(text: _telegramDisplay(user?.telegram));
    _email = TextEditingController(text: user?.email ?? '');
  }

  /// Username only → `@nick`; empty → blank. Phone values are ignored.
  static String _telegramDisplay(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return '';
    var nick = text;
    if (nick.toLowerCase().startsWith('https://t.me/')) {
      nick = nick.substring('https://t.me/'.length).split('?').first.split('/').first;
    } else if (nick.toLowerCase().startsWith('t.me/')) {
      nick = nick.substring('t.me/'.length).split('?').first.split('/').first;
    }
    nick = nick.replaceFirst(RegExp(r'^@'), '');
    if (nick.isEmpty || RegExp(r'^[\d+\s\-()]+$').hasMatch(nick)) return '';
    return '@$nick';
  }

  String? _normalizeTelegram(String raw) {
    var tg = raw.trim();
    if (tg.isEmpty) return '';
    if (tg.toLowerCase().startsWith('https://t.me/')) {
      tg = tg.substring('https://t.me/'.length).split('?').first.split('/').first;
    } else if (tg.toLowerCase().startsWith('t.me/')) {
      tg = tg.substring('t.me/'.length).split('?').first.split('/').first;
    }
    final nick = tg.replaceFirst(RegExp(r'^@'), '');
    if (nick.isEmpty) return '';
    if (RegExp(r'^[\d+\s\-()]+$').hasMatch(nick) || RuPhone.nationalDigits(nick).length >= 10) {
      return null;
    }
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{4,31}$').hasMatch(nick)) {
      return null;
    }
    return nick;
  }

  @override
  void dispose() {
    _name.dispose();
    _surname.dispose();
    _phone.dispose();
    _whatsapp.dispose();
    _telegram.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final phoneApi = RuPhone.toApi(_phone.text);
    if (phoneApi == null || RuPhone.nationalDigits(_phone.text).length < 10) {
      Toast.error('Укажите телефон');
      return;
    }
    final waDigits = RuPhone.nationalDigits(_whatsapp.text);
    if (_whatsapp.text.trim().isNotEmpty && waDigits.isNotEmpty && waDigits.length < 10) {
      Toast.error('Некорректный WhatsApp');
      return;
    }
    final waApi = waDigits.length < 10 ? '' : (RuPhone.toApi(_whatsapp.text) ?? '');
    final tgNorm = _normalizeTelegram(_telegram.text);
    if (tgNorm == null) {
      Toast.error('Некорректный Telegram (@username)');
      return;
    }

    setState(() => _saving = true);
    try {
      final user = await FitApi.patchMe(
        firstName: capitalizeWords(_name.text.trim()),
        lastName: capitalizeWords(_surname.text.trim()),
        phone: phoneApi,
        whatsapp: waApi,
        telegram: tgNorm,
      );
      ref.read(fitSessionProvider.notifier).signIn(user);
      if (!mounted) return;
      Toast.success('Сохранено');
      context.pop();
    } catch (error) {
      if (!mounted) return;
      Toast.error(FitApi.messageOf(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          FitPageTitle(
            title: 'Личные данные',
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: 12),
          FitField(label: 'Имя', controller: _name, textCapitalization: TextCapitalization.words),
          const SizedBox(height: 12),
          FitField(label: 'Фамилия', controller: _surname, textCapitalization: TextCapitalization.words),
          const SizedBox(height: 12),
          FitField(
            label: 'Телефон',
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: const [RuPhoneInputFormatter()],
            autofillHints: const [AutofillHints.telephoneNumber],
          ),
          const SizedBox(height: 12),
          FitField(
            label: 'WhatsApp',
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            inputFormatters: const [RuPhoneInputFormatter(allowEmpty: true)],
            autofillHints: const [],
            enableSuggestions: false,
          ),
          const SizedBox(height: 12),
          FitField(
            label: 'Telegram',
            controller: _telegram,
            keyboardType: TextInputType.text,
            onChanged: (value) {
              final trimmed = value.trimLeft();
              if (trimmed.isNotEmpty && !trimmed.startsWith('@') && !trimmed.contains('t.me/')) {
                final next = '@$trimmed';
                _telegram.value = TextEditingValue(
                  text: next,
                  selection: TextSelection.collapsed(offset: next.length),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          FitField(label: 'Email', controller: _email, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 24),
          FitAccentButton(
            title: 'Сохранить',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

class AddClientPage extends StatefulWidget {
  const AddClientPage({super.key});

  @override
  State<AddClientPage> createState() => _AddClientPageState();
}

class _DbClient {
  const _DbClient({
    required this.userId,
    required this.name,
    required this.goals,
    required this.place,
    required this.online,
    required this.alreadyAdded,
  });

  final int userId;
  final String name;
  final int goals;
  final String place;
  final bool online;
  final bool alreadyAdded;
}

class _AddClientPageState extends State<AddClientPage> {
  int _tab = 0;
  final _query = TextEditingController();
  List<_DbClient> _found = const [];
  bool _searching = false;
  String? _error;
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    _searchTimer?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _found = const [];
        _error = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final users = await FitApi.searchClients(query);
        if (!mounted) return;
        setState(() {
          _found = users
              .map(
                (user) => _DbClient(
                  userId: user.userId,
                  name: user.name,
                  goals: user.goals,
                  place: user.place,
                  online: user.online,
                  alreadyAdded: user.alreadyAdded,
                ),
              )
              .toList();
          _error = null;
          _searching = false;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _found = const [];
          _error = FitApi.messageOf(error);
          _searching = false;
        });
      }
    });
  }

  Future<void> _addFound(_DbClient client) async {
    if (client.alreadyAdded) {
      Toast.info('Клиент уже добавлен');
      return;
    }
    try {
      await FitApi.addClient(client.userId);
      if (mounted) context.pop();
    } catch (error) {
      if (!mounted) return;
      Toast.error(FitApi.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim();
    final found = _found;
    final missing = query.isNotEmpty && !_searching && found.isEmpty;
    return FitScaffold(
      child: Column(
        children: [
          const HubBackTitle(title: 'Добавить клиента'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF3A3A3A)),
              ),
              child: Row(
                children: [
                  _SearchTab(label: 'Поиск по базе', active: _tab == 0, onTap: () => setState(() => _tab = 0)),
                  _SearchTab(label: 'Добавить вручную', active: _tab == 1, onTap: () => setState(() => _tab = 1)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_tab == 0)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _query,
                      onChanged: _onQuery,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Телефон, Email или ID клиента',
                        hintStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: AppColors.fitGrey, size: 20),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        border: _searchBorder(missing),
                        enabledBorder: _searchBorder(missing),
                        focusedBorder: _searchBorder(missing),
                      ),
                    ),
                    if (missing) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error ?? 'Пользователи не найдены', style: const TextStyle(color: AppColors.fitGrey, fontSize: 14)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (query.isEmpty)
                      const Expanded(child: _SearchEmpty())
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: found.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) => _FoundClientCard(
                            client: found[index],
                            onAdd: () => _addFound(found[index]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            const Expanded(child: _ManualClientForm()),
        ],
      ),
    );
  }

  OutlineInputBorder _searchBorder(bool missing) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: missing ? const Color(0xFFC7F137) : const Color(0xFF3A3A3A)),
    );
  }
}

class _SearchTab extends StatelessWidget {
  const _SearchTab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2A2A2A) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFFC7F137) : const Color(0xFFB5B5B5),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SearchMark(),
        SizedBox(height: 16),
        Text('Поиск клиентов', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        Text(
          'Введите номер телефона, Email, или ID клиента, чтобы найти его в базе и добавить к себе.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF979797), fontSize: 14, height: 1.35),
        ),
        SizedBox(height: 80),
      ],
    );
  }
}

class _SearchMark extends StatelessWidget {
  const _SearchMark();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset('assets/icons/usefull/search-client.svg', width: 140, height: 70);
  }
}

class _FoundClientCard extends StatelessWidget {
  const _FoundClientCard({required this.client, required this.onAdd});

  final _DbClient client;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF232323),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF323232)),
      ),
      child: Row(
        children: [
          HubAvatar(letter: client.name, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(client.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _AddChip(asset: 'assets/icons/usefull/goals-fill.svg', label: 'Целей: ${client.goals}'),
                    _AddChip(
                      asset: client.online ? 'assets/icons/usefull/online.svg' : 'assets/icons/usefull/zal.svg',
                      label: client.place,
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF3A3A3A)),
              ),
              child: const Icon(Icons.add, color: Color(0xFFC7F137), size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.asset, required this.label});

  final String asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(asset, width: 20, height: 20),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
        ],
      ),
    );
  }
}

class ReadyWorkoutsPage extends StatefulWidget {
  const ReadyWorkoutsPage({super.key, this.pro = false, this.source});

  final bool pro;
  final String? source;

  @override
  State<ReadyWorkoutsPage> createState() => _ReadyWorkoutsPageState();
}

class _ReadyWorkoutsPageState extends State<ReadyWorkoutsPage> {
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await FitApi.programs(source: widget.source, isPro: widget.pro ? true : null);
      if (mounted) setState(() => _items = items);
    } catch (_) {}
  }

  String _level(String raw) {
    return switch (raw) {
      'beginner' => 'Начальный',
      'intermediate' => 'Средний',
      'advanced' => 'Продвинутый',
      _ => raw,
    };
  }

  String _goalLabel(String raw) {
    final code = raw.trim().toLowerCase();
    for (final goal in _fallbackGoals) {
      if (goal.code == code) return goal.title;
    }
    return switch (code) {
      'lose_weight' || 'weight_loss' || 'fat_loss' => 'Похудение',
      'gain_muscle' || 'muscle_gain' || 'mass' || 'hypertrophy' => 'Набор массы',
      'shape' || 'maintain' || 'maintenance' => 'Поддержание формы',
      'strength' => 'Развитие силы',
      'relief' || 'definition' || 'toning' => 'Рельеф',
      'flexibility' || 'mobility' => 'Гибкость',
      'rehab' || 'rehabilitation' || 'recovery' => 'Реабилитация',
      'endurance' || 'stamina' || 'cardio' => 'Выносливость',
      'health' || 'wellness' => 'Здоровье',
      _ => raw.contains('_') || raw.contains('-')
          ? raw.replaceAll(RegExp(r'[_\-]+'), ' ')
          : raw,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          FitPageTitle(
            title: 'Готовая тренировка',
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('Программ пока нет', style: TextStyle(color: AppColors.fitGrey)))
                : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = _items[index];
                final name = item['title']?.toString() ?? 'Программа';
                final goals = item['goals'];
                final goalRaw = goals is List && goals.isNotEmpty ? goals.first.toString() : '';
                final goal = goalRaw.isEmpty ? '' : _goalLabel(goalRaw);
                final level = _level(item['level']?.toString() ?? '');
                final reps = '${item['duration_weeks'] ?? item['workouts_per_week'] ?? '—'}';
                final sets = '${item['workouts_per_week'] ?? '—'}';
                return Container(
                      decoration: BoxDecoration(color: AppColors.fitSurface, borderRadius: BorderRadius.circular(24)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 140,
                            width: double.infinity,
                            decoration: const BoxDecoration(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                              image: DecorationImage(image: AssetImage('assets/images/bg_ready.png'), fit: BoxFit.cover),
                            ),
                            padding: const EdgeInsets.all(12),
                            alignment: Alignment.topLeft,
                            child: Wrap(
                              spacing: 8,
                              children: [
                                if (level.isNotEmpty) _Chip(level, filled: true),
                                if (goal.isNotEmpty) _Chip(goal, filled: false),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                                  child: const Icon(Icons.play_arrow, color: Colors.black),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Row(
                              children: [
                                _Meta('Недель', reps),
                                const SizedBox(width: 8),
                                _Meta('В неделю', sets),
                              ],
                            ),
                          ),
                        ],
                      ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.filled});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? AppColors.accent : AppColors.fitMuted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: filled ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.fitMuted, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

const _measureLabels = <String, (String, String)>{
  'weight_kg': ('Вес', 'кг'),
  'body_fat_pct': ('Жир', '%'),
  'chest_cm': ('Грудь', 'см'),
  'back_cm': ('Спина', 'см'),
  'waist_cm': ('Талия', 'см'),
  'hips_cm': ('Бедра', 'см'),
  'thigh_cm': ('Квадрицепс', 'см'),
  'calf_cm': ('Икры', 'см'),
  'shoulders_cm': ('Плечи', 'см'),
  'neck_cm': ('Шея', 'см'),
  'arm_left_cm': ('Бицепс', 'см'),
  'arm_right_cm': ('Трицепс', 'см'),
  'arm_cm': ('Рука', 'см'),
  'forearm_cm': ('Предплечье', 'см'),
};

class MeasurementsPage extends StatefulWidget {
  const MeasurementsPage({super.key});

  @override
  State<MeasurementsPage> createState() => _MeasurementsPageState();
}

class _MeasurementsPageState extends State<MeasurementsPage> {
  List<(DateTime, String, String, String)> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await FitApi.clientMeasurements();
      final rows = <(DateTime, String, String, String)>[];
      for (final item in items) {
        final at = DateTime.tryParse(item['recorded_at']?.toString() ?? item['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now();
        for (final entry in _measureLabels.entries) {
          final raw = item[entry.key];
          if (raw == null || '$raw'.isEmpty || '$raw' == 'null') continue;
          rows.add((at, entry.value.$1, entry.value.$2, '$raw'));
        }
      }
      if (mounted) setState(() => _rows = rows);
    } catch (_) {}
  }

  Future<void> _addMeasurement() async {
    final weight = TextEditingController();
    final waist = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Новый замер', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'Вес, кг'),
            ),
            TextField(
              controller: waist,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'Талия, см'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true) return;
    final body = <String, num>{};
    final w = num.tryParse(weight.text.replaceAll(',', '.'));
    final waistValue = num.tryParse(waist.text.replaceAll(',', '.'));
    if (w != null) body['weight_kg'] = w;
    if (waistValue != null) body['waist_cm'] = waistValue;
    if (body.isEmpty) {
      Toast.info('Введите хотя бы одно значение');
      return;
    }
    try {
      await FitApi.createMeasurement(body);
      await _load();
      if (mounted) Toast.success('Замер сохранён');
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          FitPageTitle(
            title: 'Замеры',
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
            ),
            trailing: IconButton(
              onPressed: _addMeasurement,
              icon: const Icon(Icons.add_circle_outline, color: AppColors.accent, size: 28),
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? const Center(child: Text('Замеров пока нет', style: TextStyle(color: AppColors.fitGrey)))
                : ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (context, index) {
                final measurement = _rows[index];
                final created = measurement.$1;
                final name = measurement.$2;
                final unit = measurement.$3;
                final value = measurement.$4;
                return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.fitSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF374151)),
                          ),
                          child: Column(
                            children: [
                              Text('${created.day}', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                              Text('${created.month}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.fitSurface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFF374151)),
                            ),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: value, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                                  TextSpan(text: ' $unit  ', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  TextSpan(text: name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

const _fallbackGoals = <({String code, String title})>[
  (code: 'weight_loss', title: 'Похудение'),
  (code: 'mass', title: 'Набор массы'),
  (code: 'shape', title: 'Поддержание формы'),
  (code: 'strength', title: 'Развитие силы'),
  (code: 'relief', title: 'Рельеф'),
  (code: 'flexibility', title: 'Гибкость'),
  (code: 'rehab', title: 'Реабилитация'),
  (code: 'endurance', title: 'Выносливость'),
];

const _formats = <({String code, String title})>[
  (code: 'gym', title: 'Зал'),
  (code: 'online', title: 'Онлайн'),
  (code: 'hybrid', title: 'Зал и Онлайн'),
];

const _measureFields = <({String key, String label, String hint})>[
  (key: 'chest_cm', label: 'Грудь', hint: 'Объем груди'),
  (key: 'back_cm', label: 'Спина', hint: 'Объем спины'),
  (key: 'arm_left_cm', label: 'Бицепс', hint: 'Объем бицепсов'),
  (key: 'arm_right_cm', label: 'Трицепс', hint: 'Объем трицепсов'),
  (key: 'shoulders_cm', label: 'Плечи', hint: 'Объем плеч'),
  (key: 'calf_cm', label: 'Икры', hint: 'Объем икр'),
  (key: 'thigh_cm', label: 'Квадрицепс', hint: 'Объем квадрицепса'),
  (key: 'hips_cm', label: 'Бедра', hint: 'Объем бедер'),
];

class _ManualClientForm extends StatefulWidget {
  const _ManualClientForm();

  @override
  State<_ManualClientForm> createState() => _ManualClientFormState();
}

class _ManualClientFormState extends State<_ManualClientForm> {
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController(text: RuPhone.formatDisplay(null));
  final _measures = {for (final field in _measureFields) field.key: TextEditingController()};
  final _notes = <TextEditingController>[TextEditingController()];
  List<({String code, String title})> _goalOptions = _fallbackGoals;
  final _goals = <String>{};
  String? _format;
  DateTime? _birth;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  Future<void> _loadGoals() async {
    try {
      final goals = await FitApi.fitnessGoals();
      if (goals.isNotEmpty && mounted) setState(() => _goalOptions = goals);
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _surname.dispose();
    _email.dispose();
    _phone.dispose();
    for (final controller in _measures.values) {
      controller.dispose();
    }
    for (final controller in _notes) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _ready {
    final hasContact = _email.text.contains('@') || RuPhone.nationalDigits(_phone.text).length >= 10;
    return _name.text.trim().isNotEmpty && hasContact && !_saving;
  }

  String get _goalLabel {
    final titles = _goalOptions.where((item) => _goals.contains(item.code)).map((item) => item.title).toList();
    if (titles.isEmpty) return 'Не выбрано';
    if (titles.length <= 2) return titles.join(', ');
    return '${titles[0]}, ${titles[1]}, +${titles.length - 2}';
  }

  String get _formatLabel => _formats.where((item) => item.code == _format).map((item) => item.title).firstOrNull ?? 'Не выбрано';

  String get _birthLabel {
    final date = _birth;
    if (date == null) return 'ДД.ММ.ГГГГ';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showBirthDateWheel(context, initial: _birth);
    if (picked != null) setState(() => _birth = picked);
  }

  Future<void> _pickGoals() async {
    final selected = Set<String>.from(_goals);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      barrierColor: const Color(0x80232323),
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFF3A3A3A), borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 16),
                  const Text('Выберите цели', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _goalOptions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF2A2A2A)),
                      itemBuilder: (context, index) {
                        final goal = _goalOptions[index];
                        final on = selected.contains(goal.code);
                        return InkWell(
                          onTap: () => setSheet(() => on ? selected.remove(goal.code) : selected.add(goal.code)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              children: [
                                _CheckBox(checked: on),
                                const SizedBox(width: 12),
                                Text(goal.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => setSheet(selected.clear),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC7F137),
                        side: const BorderSide(color: Color(0xFF3A3A3A)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Сбросить всё', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, selected),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFC7F137),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: Text('Применить (${selected.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (result != null) setState(() => _goals..clear()..addAll(result));
  }

  Future<void> _pickFormat() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      barrierColor: const Color(0x80232323),
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFF3A3A3A), borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 16),
              const Text('Формат тренировки', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final format in _formats)
                InkWell(
                  onTap: () => Navigator.pop(context, format.code),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Expanded(child: Text(format.title, style: const TextStyle(color: Colors.white, fontSize: 16))),
                        _RadioMark(selected: _format == format.code),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (result != null) setState(() => _format = result);
  }

  Future<void> _save() async {
    final measurements = <String, num>{};
    for (final field in _measureFields) {
      final raw = _measures[field.key]!.text.trim().replaceAll(',', '.');
      final value = num.tryParse(raw);
      if (value != null) measurements[field.key] = value;
    }
    final notes = _notes.map((item) => item.text.trim()).where((item) => item.isNotEmpty).toList();
    final birth = _birth;
    setState(() => _saving = true);
    try {
      await FitApi.addClientManual(
        firstName: capitalizeWords(_name.text.trim()),
        lastName: capitalizeWords(_surname.text.trim()),
        email: _email.text.trim(),
        phone: RuPhone.toApi(_phone.text) ?? '',
        birthDate: birth == null ? null : '${birth.year}-${birth.month.toString().padLeft(2, '0')}-${birth.day.toString().padLeft(2, '0')}',
        goals: _goals.toList(),
        trainingFormat: _format,
        measurements: measurements,
        contraindications: notes,
      );
      if (mounted) context.pop();
    } catch (error) {
      if (!mounted) return;
      Toast.error(FitApi.messageOf(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        _FormCard(
          title: 'Общая информация',
          child: Column(
            children: [
              _Entry(
                label: 'Имя',
                hint: 'Введите имя',
                controller: _name,
                capitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              _Entry(label: 'Фамилия', hint: 'Введите фамилию', controller: _surname, capitalization: TextCapitalization.words),
              _Entry(label: 'Email', hint: 'Введите email', controller: _email, keyboard: TextInputType.emailAddress, onChanged: (_) => setState(() {})),
              _Entry(
                label: 'Номер телефона',
                hint: '+7 999-999-99-99',
                controller: _phone,
                keyboard: TextInputType.phone,
                inputFormatters: const [RuPhoneInputFormatter()],
                onChanged: (_) => setState(() {}),
              ),
              _Entry(label: 'Дата рождения', hint: _birthLabel, valueColor: _birth == null ? AppColors.fitGrey : Colors.white, onTap: _pickDate, suffix: const Icon(Icons.calendar_month, color: Color(0xFFC7F137), size: 20)),
              _Entry(label: 'Цель', hint: _goalLabel, valueColor: _goals.isEmpty ? AppColors.fitGrey : Colors.white, onTap: _pickGoals, suffix: const Icon(Icons.keyboard_arrow_down, color: Colors.white)),
              _Entry(label: 'Формат тренировки', hint: _formatLabel, valueColor: _format == null ? AppColors.fitGrey : Colors.white, onTap: _pickFormat, suffix: const Icon(Icons.keyboard_arrow_down, color: Colors.white), last: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _FormCard(
          title: 'Замеры',
          child: Column(
            children: [
              for (var i = 0; i < _measureFields.length; i += 2)
                Padding(
                  padding: EdgeInsets.only(bottom: i + 2 < _measureFields.length ? 12 : 0),
                  child: Row(
                    children: [
                      Expanded(child: _MeasureBox(field: _measureFields[i], controller: _measures[_measureFields[i].key]!)),
                      const SizedBox(width: 10),
                      Expanded(child: _MeasureBox(field: _measureFields[i + 1], controller: _measures[_measureFields[i + 1].key]!)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _FormCard(
          title: 'Заметки',
          trailing: GestureDetector(
            onTap: () => setState(() => _notes.add(TextEditingController())),
            child: const Text('Добавить  ›', style: TextStyle(color: Color(0xFFC7F137), fontWeight: FontWeight.w700)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _notes.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _Entry(
                  label: 'Противопоказания',
                  hint: 'Введите противопоказания',
                  controller: _notes[i],
                  onChanged: (_) => setState(() {}),
                  suffix: _notes[i].text.isEmpty
                      ? null
                      : GestureDetector(
                          onTap: () {
                            setState(() {
                              if (_notes.length == 1) {
                                _notes.first.clear();
                              } else {
                                _notes.removeAt(i).dispose();
                              }
                            });
                          },
                          child: const Icon(Icons.delete_outline, color: Color(0xFFFD6565), size: 20),
                        ),
                  last: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FitAccentButton(title: 'Добавить', loading: _saving, onPressed: _ready ? _save : null),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.label,
    required this.hint,
    this.controller,
    this.keyboard,
    this.onChanged,
    this.onTap,
    this.suffix,
    this.valueColor,
    this.last = false,
    this.inputFormatters,
    this.capitalization = TextCapitalization.none,
  });

  final String label;
  final String hint;
  final TextEditingController? controller;
  final TextInputType? keyboard;
  final TextCapitalization capitalization;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final Widget? suffix;
  final Color? valueColor;
  final bool last;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final field = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: const Color(0xFF101010), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: onTap != null
                ? Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: valueColor ?? AppColors.fitGrey, fontSize: 15))
                : TextField(
                    controller: controller,
                    keyboardType: keyboard,
                    onChanged: onChanged,
                    inputFormatters: capitalization == TextCapitalization.words
                        ? [...?inputFormatters, const CapitalizeWordsFormatter()]
                        : inputFormatters,
                    textCapitalization: keyboard == TextInputType.emailAddress ? TextCapitalization.none : capitalization,
                    autocorrect: keyboard != TextInputType.emailAddress,
                    enableSuggestions: keyboard != TextInputType.emailAddress,
                    smartDashesType: keyboard == TextInputType.emailAddress ? SmartDashesType.disabled : null,
                    smartQuotesType: keyboard == TextInputType.emailAddress ? SmartQuotesType.disabled : null,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    cursorColor: const Color(0xFFC7F137),
                    decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 15), border: InputBorder.none, isCollapsed: true),
                  ),
          ),
          ?suffix,
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
          const SizedBox(height: 6),
          onTap == null ? field : GestureDetector(onTap: onTap, child: field),
        ],
      ),
    );
  }
}

class _MeasureBox extends StatelessWidget {
  const _MeasureBox({required this.field, required this.controller});

  final ({String key, String label, String hint}) field;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFF101010), borderRadius: BorderRadius.circular(14)),
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), _OneDecimalFormatter()],
            style: const TextStyle(color: Colors.white, fontSize: 15),
            cursorColor: const Color(0xFFC7F137),
            decoration: InputDecoration(
              hintText: field.hint,
              hintStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
              suffixText: 'см',
              suffixStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 14),
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _OneDecimalFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(',', '.');
    if (text.isEmpty || RegExp(r'^\d{0,3}(\.\d{0,1})?$').hasMatch(text)) {
      return newValue.copyWith(text: text);
    }
    return oldValue;
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: checked ? const Color(0xFFC7F137) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: checked ? const Color(0xFFC7F137) : const Color(0xFF6B6B6B)),
      ),
      child: checked ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
    );
  }
}

class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? const Color(0xFFC7F137) : const Color(0xFF6B6B6B), width: 1.6),
      ),
      child: selected ? Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFFC7F137), shape: BoxShape.circle)) : null,
    );
  }
}
