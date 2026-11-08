import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/shell/fit_shell.dart';
import 'package:trainhub/features/fitpro/timer/precise_clock.dart';
import 'package:trainhub/features/fitpro/timer/tabata_engine.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';

/// Clear floating pill nav (bar + gap + home indicator).
double _navClearance(BuildContext context) => FitShell.contentClearance(context);

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  static const _modes = ['Таймер', 'Табата', 'Секундомер'];
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const FitPageTitle(title: 'Таймер'),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.fitCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.fitMuted),
            ),
            child: Row(
              children: [
                for (var i = 0; i < _modes.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _mode = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _mode == i ? AppColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _modes[i],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _mode == i ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: IndexedStack(
              index: _mode,
              children: const [
                _CountdownPane(),
                _TabataPane(),
                _StopwatchPane(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ordinary countdown ───────────────────────────────────────────────────────

class _CountdownPane extends StatefulWidget {
  const _CountdownPane();

  @override
  State<_CountdownPane> createState() => _CountdownPaneState();
}

class _CountdownPaneState extends State<_CountdownPane> with WidgetsBindingObserver {
  static const _presets = [1, 3, 5, 10];
  int _seconds = 3 * 60;
  late final PreciseCountdown _clock = PreciseCountdown(
    onTick: () {
      if (mounted) setState(() {});
    },
    onFinished: () {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);
      if (mounted) Toast.success('Время вышло');
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _clock.sync();
  }

  void _toggle() {
    if (_clock.isRunning) {
      _clock.pause();
      return;
    }
    if (_clock.remaining > Duration.zero) {
      _clock.resume();
      return;
    }
    if (_seconds <= 0) {
      Toast.info('Укажите время');
      return;
    }
    _clock.start(Duration(seconds: _seconds));
  }

  void _reset() {
    _clock.stop();
    setState(() {});
  }

  bool get _idle => !_clock.isRunning && _clock.remaining <= Duration.zero;

  Future<void> _pickCustom() async {
    final picked = await showTimerDurationWheel(context, initial: Duration(seconds: _seconds));
    if (picked == null || !mounted) return;
    if (picked.inSeconds <= 0) {
      Toast.info('Время должно быть больше нуля');
      return;
    }
    setState(() => _seconds = picked.inSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final display = _idle ? _seconds : _clock.remainingSeconds;
    final isPreset = _presets.any((m) => m * 60 == _seconds);
    return Column(
      children: [
        const Spacer(),
        GestureDetector(
          onTap: _idle ? _pickCustom : null,
          child: Text(
            formatMmSs(display),
            style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.w700, height: 1),
          ),
        ),
        if (_idle) ...[
          const SizedBox(height: 8),
          const Text('Нажмите на время, чтобы задать своё', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        if (_idle)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final value in _presets)
                _TimeChip(
                  label: '$value мин',
                  active: value * 60 == _seconds,
                  onTap: () => setState(() => _seconds = value * 60),
                ),
              _TimeChip(
                label: isPreset ? 'Своё' : formatMmSs(_seconds),
                icon: Icons.edit_outlined,
                active: !isPreset,
                onTap: _pickCustom,
              ),
            ],
          ),
        const Spacer(),
        FitAccentButton(title: _clock.isRunning ? 'Пауза' : 'Старт', onPressed: _toggle),
        if (_clock.remaining > Duration.zero || _clock.isRunning) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _reset,
            child: const Text('Сброс', style: TextStyle(color: AppColors.accent)),
          ),
        ],
        SizedBox(height: _navClearance(context)),
      ],
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.active, required this.onTap, this.icon});

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.black : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : AppColors.fitSurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Stopwatch ────────────────────────────────────────────────────────────────

class _StopwatchPane extends StatefulWidget {
  const _StopwatchPane();

  @override
  State<_StopwatchPane> createState() => _StopwatchPaneState();
}

class _StopwatchPaneState extends State<_StopwatchPane> with WidgetsBindingObserver {
  late final PreciseClock _clock = PreciseClock(
    onTick: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _clock.sync();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _clock.elapsed.inSeconds;
    return Column(
      children: [
        const Spacer(),
        Text(
          formatMmSs(seconds),
          style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.w700, height: 1),
        ),
        const Spacer(),
        FitAccentButton(
          title: _clock.isRunning ? 'Стоп' : 'Старт',
          onPressed: () => _clock.isRunning ? _clock.pause() : _clock.start(),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _clock.reset,
          child: const Text('Сброс', style: TextStyle(color: AppColors.accent)),
        ),
        SizedBox(height: _navClearance(context)),
      ],
    );
  }
}

// ─── Tabata ───────────────────────────────────────────────────────────────────

class _TabataPane extends StatefulWidget {
  const _TabataPane();

  @override
  State<_TabataPane> createState() => _TabataPaneState();
}

class _TabataPaneState extends State<_TabataPane> with WidgetsBindingObserver {
  TabataConfig _config = const TabataConfig();
  late final TabataRunner _runner = TabataRunner(
    onChanged: () {
      if (mounted) setState(() {});
    },
    onPhaseChanged: (_) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    },
    onCompleted: () {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);
      if (mounted) Toast.success('Тренировка завершена');
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _runner.sync();
  }

  void _start() {
    final plan = buildTabataPlan(_config);
    if (plan.isEmpty) {
      Toast.info('Добавьте хотя бы один рабочий интервал');
      return;
    }
    _runner.start(_config);
  }

  Future<void> _confirmStop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.fitCard,
        title: const Text('Завершить тренировку?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Текущий прогресс будет сброшен.',
          style: TextStyle(color: AppColors.fitGrey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Завершить', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
    if (ok == true) _runner.resetToSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_runner.isCompleted) return _TabataDone(onAgain: () => setState(() => _runner.resetToSettings()));
    if (_runner.isActive || _runner.currentStep != null) {
      return _TabataActive(
        runner: _runner,
        onPauseResume: () => _runner.isRunning ? _runner.pause() : _runner.resume(),
        onStop: _confirmStop,
      );
    }
    return _TabataSettings(
      config: _config,
      onChanged: (value) => setState(() => _config = value.clamped()),
      onStart: _start,
    );
  }
}

class _TabataSettings extends StatelessWidget {
  const _TabataSettings({
    required this.config,
    required this.onChanged,
    required this.onStart,
  });

  final TabataConfig config;
  final ValueChanged<TabataConfig> onChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              const Text(
                'Настройка интервалов',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Параметры сохраняются при переключении режимов',
                style: TextStyle(color: AppColors.fitGrey, fontSize: 13),
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                children: [
                  _DurationStepper(
                    label: 'Подготовка',
                    value: config.warmup,
                    onChanged: (v) => onChanged(config.copyWith(warmup: v)),
                  ),
                  _DurationStepper(
                    label: 'Работа',
                    value: config.work,
                    min: const Duration(seconds: 1),
                    onChanged: (v) => onChanged(config.copyWith(work: v)),
                  ),
                  _DurationStepper(
                    label: 'Отдых',
                    value: config.rest,
                    onChanged: (v) => onChanged(config.copyWith(rest: v)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SettingsCard(
                children: [
                  _IntStepper(
                    label: 'Циклы',
                    value: config.cycles,
                    min: 1,
                    max: TabataConfig.maxCycles,
                    onChanged: (v) => onChanged(config.copyWith(cycles: v)),
                  ),
                  _IntStepper(
                    label: 'Сеты',
                    value: config.sets,
                    min: 1,
                    max: TabataConfig.maxSets,
                    onChanged: (v) => onChanged(config.copyWith(sets: v)),
                  ),
                  _DurationStepper(
                    label: 'Отдых между сетами',
                    value: config.setRest,
                    onChanged: (v) => onChanged(config.copyWith(setRest: v)),
                  ),
                  _DurationStepper(
                    label: 'Завершение',
                    value: config.cooldown,
                    onChanged: (v) => onChanged(config.copyWith(cooldown: v)),
                    last: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        FitAccentButton(title: 'Старт', onPressed: onStart),
        SizedBox(height: _navClearance(context)),
      ],
    );
  }
}

class _TabataActive extends StatelessWidget {
  const _TabataActive({
    required this.runner,
    required this.onPauseResume,
    required this.onStop,
  });

  final TabataRunner runner;
  final VoidCallback onPauseResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final step = runner.currentStep;
    if (step == null) return const SizedBox.shrink();
    final phaseColor = step.phase.isWork
        ? AppColors.accent
        : step.phase.isRestLike
            ? const Color(0xFF6EA8FE)
            : step.phase == TabataPhase.warmup || step.phase == TabataPhase.cooldown
                ? const Color(0xFFFFC857)
                : Colors.white;
    final progress = runner.overallProgress;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.fitCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: phaseColor.withValues(alpha: 0.45)),
          ),
          child: Column(
            children: [
              Text(
                step.phase.title,
                style: TextStyle(color: phaseColor, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (step.cycle > 0) ...[
                    Text(
                      'Цикл ${step.cycle}/${step.totalCycles}',
                      style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (step.setIndex > 0)
                    Text(
                      'Сет ${step.setIndex}/${step.totalSets}',
                      style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        Text(
          formatMmSs(runner.remainingSeconds),
          style: TextStyle(color: phaseColor, fontSize: 80, fontWeight: FontWeight.w800, height: 1),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppColors.fitMuted,
            color: phaseColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(progress * 100).round()}% тренировки',
          style: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
        ),
        const Spacer(),
        FitAccentButton(
          title: runner.isRunning ? 'Пауза' : 'Продолжить',
          onPressed: onPauseResume,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onStop,
          child: const Text('Завершить', style: TextStyle(color: Color(0xFFFF6B6B))),
        ),
        SizedBox(height: _navClearance(context)),
      ],
    );
  }
}

class _TabataDone extends StatelessWidget {
  const _TabataDone({required this.onAgain});

  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.black, size: 36),
        ),
        const SizedBox(height: 16),
        const Text(
          'Тренировка завершена',
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Отличная работа. Можно запустить ещё раз.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.fitGrey),
        ),
        const Spacer(),
        FitAccentButton(title: 'К настройкам', onPressed: onAgain),
        SizedBox(height: _navClearance(context)),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.fitCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.fitMuted),
      ),
      child: Column(children: children),
    );
  }
}

class _DurationStepper extends StatelessWidget {
  const _DurationStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = Duration.zero,
    this.last = false,
  });

  final String label;
  final Duration value;
  final ValueChanged<Duration> onChanged;
  final Duration min;
  final bool last;

  static const _step = Duration(seconds: 1);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 8 : 0, top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          _RoundBtn(
            icon: Icons.remove,
            onTap: () {
              final next = value - _step;
              onChanged(next < min ? min : next);
            },
          ),
          SizedBox(
            width: 64,
            child: Text(
              formatDurationMmSs(value),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          _RoundBtn(
            icon: Icons.add,
            onTap: () {
              final next = value + _step;
              onChanged(next > TabataConfig.maxDuration ? TabataConfig.maxDuration : next);
            },
          ),
        ],
      ),
    );
  }
}

class _IntStepper extends StatelessWidget {
  const _IntStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          _RoundBtn(icon: Icons.remove, onTap: () => onChanged((value - 1).clamp(min, max))),
          SizedBox(
            width: 64,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          _RoundBtn(icon: Icons.add, onTap: () => onChanged((value + 1).clamp(min, max))),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fitMuted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
