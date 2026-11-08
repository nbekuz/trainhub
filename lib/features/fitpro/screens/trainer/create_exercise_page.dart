import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';

// ─── Static options ────────────────────────────────────────────────────────────

const _kEquipment = <({String code, String label})>[
  (code: 'barbell', label: 'Штанга'),
  (code: 'dumbbell', label: 'Гантели'),
  (code: 'machine', label: 'Тренажёр'),
  (code: 'bodyweight', label: 'Без инвентаря'),
  (code: 'kettlebell', label: 'Гиря'),
  (code: 'resistance_band', label: 'Резинка'),
  (code: 'cable', label: 'Блок/Кроссовер'),
  (code: 'trx', label: 'TRX'),
];

const _kMuscles = <({String code, String label})>[
  (code: 'chest', label: 'Грудь'),
  (code: 'back', label: 'Спина'),
  (code: 'legs', label: 'Ноги'),
  (code: 'shoulders', label: 'Плечи'),
  (code: 'arms', label: 'Руки'),
  (code: 'abs', label: 'Пресс'),
  (code: 'glutes', label: 'Ягодицы'),
  (code: 'full_body', label: 'Всё тело'),
  (code: 'calves', label: 'Икры'),
  (code: 'forearms', label: 'Предплечья'),
];

const _kTypes = <({String code, String label})>[
  (code: 'strength', label: 'Силовые'),
  (code: 'cardio', label: 'Кардио'),
  (code: 'stretching', label: 'Растяжка'),
  (code: 'functional', label: 'Функциональные'),
  (code: 'balance', label: 'Баланс'),
  (code: 'hiit', label: 'HIIT'),
  (code: 'yoga', label: 'Йога'),
  (code: 'plyometric', label: 'Плиометрия'),
];

// ─── Page ──────────────────────────────────────────────────────────────────────

class CreateExercisePage extends StatefulWidget {
  const CreateExercisePage({super.key});

  @override
  State<CreateExercisePage> createState() => _CreateExercisePageState();
}

class _CreateExercisePageState extends State<CreateExercisePage> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // single-pick
  String? _equipment;
  String? _primaryMuscle;
  String? _exerciseType;

  // multi-pick (secondary muscles)
  final Set<String> _secondaryMuscles = {};

  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _valid => _nameCtrl.text.trim().isNotEmpty && !_saving;

  // ── Bottom sheet picker ──────────────────────────────────────────────────────

  Future<String?> _pickOne(
    String title,
    List<({String code, String label})> options,
    String? current,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.fitCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, sc) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A4A4A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: sc,
                  itemCount: options.length,
                  separatorBuilder: (_, divI) => const Divider(color: Color(0xFF323232), height: 1),
                  itemBuilder: (_, i) {
                    final opt = options[i];
                    final selected = opt.code == current;
                    return ListTile(
                      title: Text(
                        opt.label,
                        style: TextStyle(
                          color: selected ? AppColors.accent : Colors.white,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check_rounded, color: AppColors.accent, size: 20)
                          : null,
                      onTap: () => Navigator.pop(ctx, opt.code),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickMulti(
    String title,
    List<({String code, String label})> options,
    Set<String> current,
    void Function(Set<String>) onDone,
  ) async {
    final result = Set<String>.from(current);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.fitCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setB) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            expand: false,
            builder: (_, sc) => Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A4A4A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx2),
                        child: const Text('Готово', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.separated(
                    controller: sc,
                    itemCount: options.length,
                    separatorBuilder: (_, divI) => const Divider(color: Color(0xFF323232), height: 1),
                    itemBuilder: (_, i) {
                      final opt = options[i];
                      final sel = result.contains(opt.code);
                      return ListTile(
                        title: Text(
                          opt.label,
                          style: TextStyle(color: sel ? AppColors.accent : Colors.white),
                        ),
                        trailing: sel ? const Icon(Icons.check_rounded, color: AppColors.accent, size: 20) : null,
                        onTap: () {
                          setB(() {
                            if (sel) {
                              result.remove(opt.code);
                            } else {
                              result.add(opt.code);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    onDone(result);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String? _labelFor(String? code, List<({String code, String label})> opts) {
    if (code == null) return null;
    return opts.where((o) => o.code == code).firstOrNull?.label;
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_valid) return;
    setState(() => _saving = true);
    try {
      await FitApi.createExercise(
        title: _nameCtrl.text.trim(),
        equipment: _equipment != null ? [_equipment!] : [],
        muscle: _primaryMuscle,
        category: _exerciseType,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      if (!mounted) return;
      Toast.success('Упражнение создано');
      context.pop();
    } catch (e) {
      if (!mounted) return;
      Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      child: Column(
        children: [
          // ── App bar ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: SvgPicture.asset(
                      'assets/icons/trainer/arrow-left.svg',
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Создать упражнение',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  GestureDetector(
                    onTap: _valid ? _save : null,
                    child: _saving
                        ? const SizedBox(
                            width: 48,
                            height: 24,
                            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))),
                          )
                        : Text(
                            'Сохранить',
                            style: TextStyle(
                              color: _valid ? AppColors.accent : AppColors.fitGrey,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                // Camera + «Добавить актив» (Figma)
                Center(
                  child: GestureDetector(
                    onTap: () => Toast.info('Добавление фото скоро будет доступно'),
                    child: Column(
                      children: [
                        Container(
                          width: 106,
                          height: 106,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF323232)),
                          ),
                          child: SvgPicture.asset(
                            'assets/icons/trainer/camera.svg',
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Добавить актив',
                          style: TextStyle(color: AppColors.accent, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Name card
                _SectionCard(
                  label: 'Название упражнения',
                  child: TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    cursorColor: AppColors.accent,
                    decoration: const InputDecoration(
                      hintText: 'Введите название',
                      hintStyle: TextStyle(color: AppColors.fitGrey, fontSize: 14),
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Equipment row
                _PickerRow(
                  label: 'Оборудование',
                  value: _labelFor(_equipment, _kEquipment),
                  onTap: () async {
                    final v = await _pickOne('Оборудование', _kEquipment, _equipment);
                    if (v != null) setState(() => _equipment = v);
                  },
                ),
                const SizedBox(height: 1),

                // Primary muscle row
                _PickerRow(
                  label: 'Основная группа мышц',
                  value: _labelFor(_primaryMuscle, _kMuscles),
                  onTap: () async {
                    final v = await _pickOne('Основная группа мышц', _kMuscles, _primaryMuscle);
                    if (v != null) setState(() => _primaryMuscle = v);
                  },
                ),
                const SizedBox(height: 1),

                // Secondary muscles row
                _PickerRow(
                  label: 'Другие мышцы',
                  value: _secondaryMuscles.isEmpty
                      ? null
                      : _secondaryMuscles
                          .map((c) => _kMuscles.where((m) => m.code == c).firstOrNull?.label ?? c)
                          .join(', '),
                  optional: true,
                  onTap: () => _pickMulti('Другие мышцы', _kMuscles, _secondaryMuscles, (v) {
                    setState(() {
                      _secondaryMuscles
                        ..clear()
                        ..addAll(v);
                    });
                  }),
                ),
                const SizedBox(height: 1),

                // Type row
                _PickerRow(
                  label: 'Тип упражнения',
                  value: _labelFor(_exerciseType, _kTypes),
                  onTap: () async {
                    final v = await _pickOne('Тип упражнения', _kTypes, _exerciseType);
                    if (v != null) setState(() => _exerciseType = v);
                  },
                ),
                const SizedBox(height: 20),

                // Description
                _SectionCard(
                  label: 'Описание (необязательно)',
                  child: TextField(
                    controller: _descCtrl,
                    minLines: 3,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    cursorColor: AppColors.accent,
                    decoration: const InputDecoration(
                      hintText: 'Техника, нюансы выполнения…',
                      hintStyle: TextStyle(color: AppColors.fitGrey, fontSize: 14),
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _SectionCard ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.fitCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF323232)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.fitGrey, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ─── _PickerRow ────────────────────────────────────────────────────────────────

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.onTap,
    this.value,
    this.optional = false,
  });

  final String label;
  final String? value;
  final bool optional;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          border: Border.all(color: const Color(0xFF323232)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Color(0xFF979797), fontSize: 14)),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: hasValue ? value! : 'Выбрать',
                          style: const TextStyle(color: AppColors.accent, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        if (optional && !hasValue)
                          const TextSpan(
                            text: ' (optional)',
                            style: TextStyle(color: Color(0xFF979797), fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SvgPicture.asset(
              'assets/icons/trainer/chevron.svg',
              width: 8,
              height: 16,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
          ],
        ),
      ),
    );
  }
}
