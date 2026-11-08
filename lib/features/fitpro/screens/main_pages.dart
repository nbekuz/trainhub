import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/shell/fit_shell.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/features/fitpro/workout_offline_queue.dart';
import 'package:trainhub/routes/route_names.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(fitSessionProvider).user;
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 140),
        children: [
          const FitPageTitle(title: 'Информация'),
          const SizedBox(height: 8),
          Row(
            children: [
              _Avatar(text: user?.initials ?? 'NB', size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${user?.name ?? 'Nodirbek'} ${user?.surname ?? 'Bek'}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    _IdChip(id: user?.uuid ?? '482910'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text('Статистика', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push(RouteNames.measurements),
                child: const Row(
                  children: [
                    Text('Замеры', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right, color: AppColors.accent, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(color: AppColors.fitSurface, borderRadius: BorderRadius.circular(24)),
            child: const Row(
              children: [
                _Stat(label: 'Рост (см)', value: '178', diff: '+0.4', up: true, good: true),
                _Stat(label: 'Вес (кг)', value: '74.2', diff: '1.1', up: false, good: true),
                _Stat(label: 'Жир (%)', value: '16.4', diff: '0.6', up: false, good: true),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _Panel(title: 'Активность', child: _Bars()),
          const SizedBox(height: 16),
          const _Panel(
            title: 'Прошлая тренировка',
            child: _LastWorkout(),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.diff, required this.up, required this.good});

  final String label;
  final String value;
  final String diff;
  final bool up;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? AppColors.fitGreen : Colors.redAccent;
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(width: 2),
              Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: color, size: 18),
              Text(diff, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LastWorkout extends StatelessWidget {
  const _LastWorkout();

  @override
  Widget build(BuildContext context) {
    return const Text('Грудь, Ноги · 12.06.2026', style: TextStyle(color: Colors.white70));
  }
}

class _Bars extends StatelessWidget {
  const _Bars();

  @override
  Widget build(BuildContext context) {
    const values = [0.4, 0.7, 0.55, 0.9, 0.35, 0.6, 0.8];
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  height: 80 * values[i],
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                ),
                const SizedBox(height: 6),
                Text(days[i], style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class WorkoutsPage extends ConsumerStatefulWidget {
  const WorkoutsPage({super.key, required this.trainer});

  final bool trainer;

  @override
  ConsumerState<WorkoutsPage> createState() => _WorkoutsPageState();
}

class _WorkoutsPageState extends ConsumerState<WorkoutsPage> {
  @override
  Widget build(BuildContext context) {
    // Trainer hub = Figma «Выберите тип тренировки» (no video create).
    // Client: own / ready / «от профи».
    if (widget.trainer) {
      return _TrainerTrainingTypeHub();
    }

    final cards = <({String title, IconData icon, String image, String? route, String? tag, bool requiresPro})>[
      (
        title: 'Своя тренировка',
        icon: Icons.fitness_center,
        image: 'assets/images/bg_own.png',
        route: RouteNames.ownWorkout,
        tag: null,
        requiresPro: false,
      ),
      (
        title: 'Готовая тренировка',
        icon: Icons.assignment_rounded,
        image: 'assets/images/bg_ready.png',
        route: RouteNames.readyWorkouts,
        tag: null,
        requiresPro: false,
      ),
      (
        title: 'Тренировки от профи',
        icon: Icons.emoji_events_rounded,
        image: 'assets/images/bg_pro.png',
        route: '${RouteNames.readyWorkouts}?pro=1',
        tag: 'PRO',
        requiresPro: true,
      ),
    ];

    final bottomPad = FitShell.contentClearance(context);

    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        padding: EdgeInsets.only(bottom: bottomPad),
        children: [
          const FitPageTitle(title: 'Тренировки'),
          const SizedBox(height: 6),
          for (var i = 0; i < cards.length; i++) ...[
            SizedBox(
              height: 128,
              child: _WorkoutCard(
                title: cards[i].title,
                icon: cards[i].icon,
                image: cards[i].image,
                tag: cards[i].tag,
                onTap: () => _openWorkout(
                  context,
                  cards[i].title,
                  cards[i].route,
                  requiresPro: cards[i].requiresPro,
                ),
              ),
            ),
            if (i != cards.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Figma Training type — trainer workouts hub.
class _TrainerTrainingTypeHub extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bottomPad = FitShell.contentClearance(context);
    final cards = <({String title, IconData icon, Color iconColor, String image, VoidCallback onTap})>[
      (
        title: 'Новая тренировка',
        icon: Icons.groups_rounded,
        iconColor: AppColors.accent,
        image: 'assets/images/bg_trainer.png',
        onTap: () => context.push(RouteNames.addCalendarEvent, extra: const {'startNow': true}),
      ),
      (
        title: 'Запланированные тренировки',
        icon: Icons.fitness_center_rounded,
        iconColor: const Color(0xFFFEB94B),
        image: 'assets/images/bg_own.png',
        onTap: () => context.push(RouteNames.plannedWorkouts),
      ),
      (
        title: 'Готовая тренировка',
        icon: Icons.assignment_rounded,
        iconColor: const Color(0xFF37D2F1),
        image: 'assets/images/bg_ready.png',
        onTap: () => context.push(RouteNames.readyWorkouts),
      ),
      (
        title: 'Сохраненные тренировки',
        icon: Icons.bookmark_rounded,
        iconColor: const Color(0xFFFD6565),
        image: 'assets/images/bg_pro.png',
        onTap: () => context.push(RouteNames.savedWorkouts),
      ),
    ];

    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        padding: EdgeInsets.only(bottom: bottomPad),
        children: [
          const FitPageTitle(title: 'Выберите тип тренировки'),
          const SizedBox(height: 10),
          for (var i = 0; i < cards.length; i++) ...[
            SizedBox(
              height: 128,
              child: _TrainingTypeCard(
                title: cards[i].title,
                icon: cards[i].icon,
                iconColor: cards[i].iconColor,
                image: cards[i].image,
                onTap: cards[i].onTap,
              ),
            ),
            if (i != cards.length - 1) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

Future<bool> _hasActiveClientPro() async {
  try {
    final sub = await FitApi.subscription('pro_client');
    return sub?['status']?.toString() == 'active';
  } catch (_) {
    return false;
  }
}

Future<void> _openWorkout(
  BuildContext context,
  String title,
  String? route, {
  bool requiresPro = false,
}) async {
  if (requiresPro) {
    final ok = await _hasActiveClientPro();
    if (!context.mounted) return;
    if (!ok) {
      Toast.info('Для доступа нужна подписка PRO');
      context.push(RouteNames.subscription);
      return;
    }
  }
  if (route != null) {
    context.push(route);
    return;
  }
  try {
    await WorkoutOfflineQueue.I.flush();
    final activeId = await WorkoutOfflineQueue.I.activeSessionId();
    if (activeId != null && activeId > 0 && context.mounted) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.fitCard,
          title: const Text('Есть незавершённая тренировка', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Продолжить её или начать новую?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Новая', style: TextStyle(color: AppColors.fitGrey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Продолжить', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (resume == true) {
        context.push(RouteNames.liveSession, extra: activeId);
        return;
      }
    }
    final result = await FitApi.startOrResumeSession();
    final sessionId = result.sessionId;
    if (context.mounted) {
      if (sessionId > 0) {
        await WorkoutOfflineQueue.I.setActiveSessionId(sessionId);
        if (result.resumed) Toast.info('Продолжаем незавершённую тренировку');
        context.push(RouteNames.liveSession, extra: sessionId);
      } else {
        Toast.success('Тренировка начата');
      }
    }
  } catch (error) {
    if (context.mounted) Toast.error(FitApi.messageOf(error));
  }
}

class _TrainingTypeCard extends StatelessWidget {
  const _TrainingTypeCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.image,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final String image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(image, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xCC000000), Color(0x66000000)],
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF323232)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF232323),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: iconColor, size: 22),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF323232)),
                    ),
                    child: const Icon(Icons.chevron_right, color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({
    required this.title,
    required this.icon,
    required this.image,
    required this.onTap,
    this.tag,
  });

  final String title;
  final IconData icon;
  final String image;
  final VoidCallback onTap;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(image, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.accent, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                  if (tag != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag!,
                        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(height: 2, child: ColoredBox(color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(fitSessionProvider).user;
    final trainer = user?.role == FitRole.trainer;
    final name = '${user?.name ?? 'Иван'} ${user?.surname ?? 'Петров'}'.trim();
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 140),
        children: [
          const FitPageTitle(title: 'Профиль'),
          Center(child: _Avatar(text: user?.initials ?? 'ИП', size: 88)),
          const SizedBox(height: 12),
          Center(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700))),
          const SizedBox(height: 4),
          Center(
            child: Text(
              trainer ? 'Персональный тренер' : 'Клиент',
              style: const TextStyle(color: AppColors.fitGrey),
            ),
          ),
          if (trainer) ...[
            const SizedBox(height: 16),
            const Row(
              children: [
                _ProfileStat(label: 'Клиентов', value: '24'),
                _ProfileStat(label: 'Опыта', value: '10'),
                _ProfileStat(label: 'Рейтинг', value: '4.9'),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _ProfileGroup(
            title: 'Аккаунт',
            tiles: [
              _MenuTile(icon: Icons.badge_outlined, label: 'Личные данные', onTap: () => context.push(RouteNames.account)),
              if (trainer) _MenuTile(icon: Icons.sell_outlined, label: 'Специализация и цены', onTap: () => context.push(RouteNames.specialization)),
              if (trainer) _MenuTile(icon: Icons.playlist_add_outlined, label: 'Создать программу', onTap: () => context.push(RouteNames.createProgram)),
              if (trainer) _MenuTile(icon: Icons.menu_book_outlined, label: 'Мои курсы', onTap: () => context.push(RouteNames.myPrograms)),
              if (trainer) _MenuTile(icon: Icons.inbox_outlined, label: 'Заявки клиентов', onTap: () => context.push(RouteNames.trainerRequests)),
              if (!trainer) _MenuTile(icon: Icons.fitness_center, label: 'Найти тренера', onTap: () => context.push(RouteNames.trainers)),
              if (!trainer) _MenuTile(icon: Icons.inbox_outlined, label: 'Мои заявки тренерам', onTap: () => context.push(RouteNames.myTrainerRequests)),
              if (!trainer) _MenuTile(icon: Icons.history, label: 'История тренировок', onTap: () => context.push(RouteNames.workoutHistory)),
              _MenuTile(icon: Icons.workspace_premium_outlined, label: 'Подписка PRO', onTap: () => context.push(RouteNames.subscription)),
            ],
          ),
          _ProfileGroup(
            title: 'Настройки',
            tiles: [
              _MenuTile(asset: 'assets/icons/usefull/ring.svg', label: 'Уведомления', onTap: () => context.push(RouteNames.notifications)),
              _MenuTile(icon: Icons.settings_outlined, label: 'Настройки приложения', onTap: () => context.push(RouteNames.settings)),
            ],
          ),
          _ProfileGroup(
            title: 'Поддержка',
            tiles: [
              _MenuTile(icon: Icons.help_outline, label: 'Центр помощи', onTap: () => context.push(RouteNames.help)),
              _MenuTile(icon: Icons.description_outlined, label: 'Условия использования', onTap: () => context.push(RouteNames.terms)),
              _MenuTile(icon: Icons.privacy_tip_outlined, label: 'Политика конфиденциальности', onTap: () => context.push(RouteNames.privacy)),
              _MenuTile(
                icon: Icons.logout,
                label: 'Выйти из аккаунта',
                danger: true,
                onTap: () async {
                  final leave = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: AppColors.fitCard,
                      title: const Text('Выйти из аккаунта?', style: TextStyle(color: Colors.white)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Остаться')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Выйти', style: TextStyle(color: Color(0xFFFF5C5C)))),
                      ],
                    ),
                  );
                  if (leave != true) return;
                  await ref.read(fitSessionProvider.notifier).logout();
                  if (context.mounted) context.go(RouteNames.welcome);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<String?> _openClientsSheet(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String selected,
}) {
  var current = selected;
  return showModalBottomSheet<String>(
    context: context,
    barrierColor: const Color(0x80232323),
    backgroundColor: const Color(0xFF1A1A1A),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF3A3A3A), borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 14),
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Column(
                    children: [
                      for (var i = 0; i < options.length; i++) ...[
                        if (i > 0) const Divider(height: 1, color: Color(0xFF2E2E2E)),
                        InkWell(
                          onTap: () {
                            setSheetState(() => current = options[i]);
                            Navigator.pop(context, options[i]);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    options[i],
                                    style: TextStyle(
                                      color: current == options[i] ? Colors.white : const Color(0xFFE6E6E6),
                                      fontSize: 16,
                                      fontWeight: current == options[i] ? FontWeight.w600 : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                Icon(
                                  current == options[i] ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: current == options[i] ? const Color(0xFFC7F137) : const Color(0xFF6B6B6B),
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _ClientFilter {
  const _ClientFilter({
    this.men = false,
    this.women = false,
    this.hall = false,
    this.online = false,
    this.fresh = false,
    this.regular = false,
  });

  final bool men;
  final bool women;
  final bool hall;
  final bool online;
  final bool fresh;
  final bool regular;

  int get count => [men, women, hall, online, fresh, regular].where((item) => item).length;

  _ClientFilter copy({
    bool? men,
    bool? women,
    bool? hall,
    bool? online,
    bool? fresh,
    bool? regular,
  }) {
    return _ClientFilter(
      men: men ?? this.men,
      women: women ?? this.women,
      hall: hall ?? this.hall,
      online: online ?? this.online,
      fresh: fresh ?? this.fresh,
      regular: regular ?? this.regular,
    );
  }
}

Future<_ClientFilter?> _openFilterSheet(BuildContext context, _ClientFilter initial) {
  var draft = initial;
  return showModalBottomSheet<_ClientFilter>(
    context: context,
    barrierColor: const Color(0x80232323),
    backgroundColor: const Color(0xFF1C1C1C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          void toggle({bool? men, bool? women, bool? hall, bool? online, bool? fresh, bool? regular}) {
            setSheetState(() => draft = draft.copy(men: men, women: women, hall: hall, online: online, fresh: fresh, regular: regular));
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF3A3A3A), borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 14),
                  const Text('Фильтр', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 18),
                  const Align(alignment: Alignment.centerLeft, child: Text('Пол', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _FilterCheck(label: 'Мужчины', value: draft.men, onTap: () => toggle(men: !draft.men)),
                      const SizedBox(width: 24),
                      _FilterCheck(label: 'Женщины', value: draft.women, onTap: () => toggle(women: !draft.women)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Align(alignment: Alignment.centerLeft, child: Text('Тип тренировок', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _FilterCheck(label: 'Зал', value: draft.hall, onTap: () => toggle(hall: !draft.hall)),
                      const SizedBox(width: 24),
                      _FilterCheck(label: 'Онлайн', value: draft.online, onTap: () => toggle(online: !draft.online)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Align(alignment: Alignment.centerLeft, child: Text('Статус клиента', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _FilterCheck(label: 'Новые', value: draft.fresh, onTap: () => toggle(fresh: !draft.fresh)),
                      const SizedBox(width: 24),
                      _FilterCheck(label: 'Постоянные', value: draft.regular, onTap: () => toggle(regular: !draft.regular)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => toggle(men: false, women: false, hall: false, online: false, fresh: false, regular: false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF323232)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Сбросить всё', style: TextStyle(color: Color(0xFFC7F137), fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(color: Color(0x40C7F137), blurRadius: 16, offset: Offset(0, 4))],
                      ),
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, draft),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC7F137),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text('Применить${draft.count == 0 ? '' : ' (${draft.count})'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _FilterCheck extends StatelessWidget {
  const _FilterCheck({required this.label, required this.value, required this.onTap});

  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: value ? const Color(0xFFC7F137) : const Color(0xFF505050)),
            ),
            child: value ? const Icon(Icons.check, size: 16, color: Color(0xFFC7F137)) : null,
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
        ],
      ),
    );
  }
}

class _SearchAction extends StatelessWidget {
  const _SearchAction({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: child,
      ),
    );
  }
}

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  String _query = '';
  _ClientFilter _filter = const _ClientFilter();
  String _sort = 'Сначала новые';
  List<FitClient> _clients = const [];
  bool _loading = true;
  bool _hasAny = false;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final gender = _filter.men == _filter.women ? null : (_filter.men ? 'male' : 'female');
    final format = _filter.hall == _filter.online ? null : (_filter.online ? 'online' : 'gym');
    final status = _filter.fresh == _filter.regular ? null : (_filter.fresh ? 'new' : 'permanent');
    final sort = switch (_sort) {
      'По алфавиту' => 'alpha',
      'Сначала старые' => 'oldest',
      'Сначала мужчины' => 'male_first',
      'Сначала женщины' => 'female_first',
      _ => 'newest',
    };
    try {
      final clients = await FitApi.trainerClients(
        q: _query.trim(),
        gender: gender,
        format: format,
        status: status,
        sort: sort,
      );
      if (!mounted) return;
      setState(() {
        _clients = clients;
        // Keep empty-state sticky only while the unfiltered list is truly empty.
        if (_query.trim().isEmpty && _filter.count == 0) {
          _hasAny = clients.isNotEmpty;
        } else if (clients.isNotEmpty) {
          _hasAny = true;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddClient() async {
    await context.push<bool>(RouteNames.addClient);
    if (!mounted) return;
    setState(() => _loading = true);
    await _load();
  }

  void _scheduleSearch(String value) {
    _query = value;
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), _load);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final clients = _clients;
    final noClients = !_loading && !_hasAny;
    return FitScaffold(
      child: Stack(
        children: [
          Column(
            children: [
              const HubBackTitle(title: 'Клиенты'),
              if (noClients)
                const Expanded(child: _ClientsEmpty())
              else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: _scheduleSearch,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Поиск по имени или телефо...',
                          hintStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 14),
                          prefixIcon: const Icon(Icons.search, color: AppColors.fitGrey, size: 20),
                          filled: true,
                          fillColor: AppColors.fitCard,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SearchAction(
                      onTap: () async {
                        final value = await _openFilterSheet(context, _filter);
                        if (value != null) {
                          setState(() => _filter = value);
                          _load();
                        }
                      },
                      child: const Icon(Icons.tune, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 8),
                    _SearchAction(
                      onTap: () async {
                        final value = await _openClientsSheet(
                          context,
                          title: 'Сортировка',
                          options: const ['По алфавиту', 'Сначала новые', 'Сначала старые', 'Сначала мужчины', 'Сначала женщины'],
                          selected: _sort,
                        );
                        if (value != null) {
                          setState(() => _sort = value);
                          _load();
                        }
                      },
                      child: SvgPicture.asset('assets/icons/usefull/sort.svg', width: 20, height: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.accent,
                  backgroundColor: const Color(0xFF232323),
                  onRefresh: _load,
                  child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
                  itemCount: clients.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final client = clients[index];
                    return GestureDetector(
                      onTap: () => context.push(RouteNames.clientDetail, extra: client.id),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF232323),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF323232)),
                        ),
                        child: Row(
                          children: [
                            _Avatar(text: client.initials, size: 48),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('${client.name} ${client.surname}'.trim(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                      if (client.isNew) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          height: 20,
                                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(color: const Color(0xFFC7F137), borderRadius: BorderRadius.circular(111)),
                                          child: const Text('Новый', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, height: 1)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _ClientChip(
                                        asset: 'assets/icons/usefull/goals-fill.svg',
                                        label: 'Целей: ${client.goals}',
                                      ),
                                      _ClientChip(
                                        asset: client.online ? 'assets/icons/usefull/online.svg' : 'assets/icons/usefull/zal.svg',
                                        label: client.place,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.fitGrey),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                ),
              ),
              ],
            ],
          ),
          if (noClients)
            const Positioned(
              right: 46,
              bottom: 186,
              child: IgnorePointer(
                child: _ClientsArrow(),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 108,
            child: GestureDetector(
              onTap: _openAddClient,
              child: Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFC7F137),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x40C7F137), blurRadius: 12),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.black, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientsEmpty extends StatelessWidget {
  const _ClientsEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 0, 32, 180),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ClientsMark(),
          SizedBox(height: 20),
          Text(
            'Пока у вас нет клиентов',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Text(
            'Как только вы добавите первого клиента, он появится здесь',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF979797), fontSize: 14, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _ClientsMark extends StatelessWidget {
  const _ClientsMark();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset('assets/icons/usefull/no-client.svg', width: 128, height: 70);
  }
}

class _ClientsArrow extends StatelessWidget {
  const _ClientsArrow();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset('assets/icons/usefull/arrow.svg', width: 149, height: 147);
  }
}

class _ClientChip extends StatelessWidget {
  const _ClientChip({required this.asset, required this.label});

  final String asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(20),
      ),
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.text, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.fitSurface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.fitMuted, width: size > 80 ? 4 : 1),
      ),
      child: Text(text, style: TextStyle(color: Colors.white, fontSize: size * 0.32, fontWeight: FontWeight.w700)),
    );
  }
}

class _IdChip extends StatelessWidget {
  const _IdChip({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: AppColors.fitSurface, borderRadius: BorderRadius.circular(20)),
      child: Text('ID$id', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ProfileGroup extends StatelessWidget {
  const _ProfileGroup({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: AppColors.fitCard, borderRadius: BorderRadius.circular(22)),
            child: Column(children: tiles),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({this.icon, this.asset, required this.label, required this.onTap, this.danger = false});

  final IconData? icon;
  final String? asset;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF5C5C) : Colors.white;
    final mark = danger ? color : AppColors.accent;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            if (asset != null)
              SvgPicture.asset(
                asset!,
                width: 15,
                height: 17,
                colorFilter: ColorFilter.mode(mark, BlendMode.srcIn),
              )
            else
              Icon(icon, color: mark),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 16))),
            if (!danger) const Icon(Icons.chevron_right, color: AppColors.fitGrey),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.fitSurface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
