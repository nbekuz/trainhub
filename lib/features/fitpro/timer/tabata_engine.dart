import 'package:trainhub/features/fitpro/timer/precise_clock.dart';

enum TabataPhase {
  warmup,
  work,
  rest,
  setRest,
  cooldown,
  done,
}

extension TabataPhaseX on TabataPhase {
  String get title => switch (this) {
        TabataPhase.warmup => 'Подготовка',
        TabataPhase.work => 'Работа',
        TabataPhase.rest => 'Отдых',
        TabataPhase.setRest => 'Отдых между сетами',
        TabataPhase.cooldown => 'Завершение',
        TabataPhase.done => 'Готово',
      };

  bool get isWork => this == TabataPhase.work;
  bool get isRestLike => this == TabataPhase.rest || this == TabataPhase.setRest;
}

class TabataConfig {
  const TabataConfig({
    this.warmup = const Duration(seconds: 10),
    this.work = const Duration(seconds: 20),
    this.rest = const Duration(seconds: 10),
    this.cycles = 8,
    this.sets = 1,
    this.setRest = const Duration(seconds: 60),
    this.cooldown = Duration.zero,
  });

  final Duration warmup;
  final Duration work;
  final Duration rest;
  final int cycles;
  final int sets;
  final Duration setRest;
  final Duration cooldown;

  static const Duration maxDuration = Duration(minutes: 30);
  static const int maxCycles = 50;
  static const int maxSets = 20;

  TabataConfig copyWith({
    Duration? warmup,
    Duration? work,
    Duration? rest,
    int? cycles,
    int? sets,
    Duration? setRest,
    Duration? cooldown,
  }) {
    return TabataConfig(
      warmup: warmup ?? this.warmup,
      work: work ?? this.work,
      rest: rest ?? this.rest,
      cycles: cycles ?? this.cycles,
      sets: sets ?? this.sets,
      setRest: setRest ?? this.setRest,
      cooldown: cooldown ?? this.cooldown,
    );
  }

  TabataConfig clamped() {
    return TabataConfig(
      warmup: _clampDuration(warmup, allowZero: true),
      work: _clampDuration(work, allowZero: false, min: const Duration(seconds: 1)),
      rest: _clampDuration(rest, allowZero: true),
      cycles: cycles.clamp(1, maxCycles),
      sets: sets.clamp(1, maxSets),
      setRest: _clampDuration(setRest, allowZero: true),
      cooldown: _clampDuration(cooldown, allowZero: true),
    );
  }

  static Duration _clampDuration(Duration value, {required bool allowZero, Duration min = Duration.zero}) {
    if (value.isNegative) return allowZero ? Duration.zero : min;
    if (value > maxDuration) return maxDuration;
    if (!allowZero && value < min) return min;
    return value;
  }
}

class TabataStep {
  const TabataStep({
    required this.phase,
    required this.duration,
    required this.cycle,
    required this.setIndex,
    required this.totalCycles,
    required this.totalSets,
    required this.stepIndex,
    required this.totalSteps,
  });

  final TabataPhase phase;
  final Duration duration;
  final int cycle;
  final int setIndex;
  final int totalCycles;
  final int totalSets;
  final int stepIndex;
  final int totalSteps;

  double get progress => totalSteps <= 0 ? 0 : (stepIndex + 1) / totalSteps;
}

List<TabataStep> buildTabataPlan(TabataConfig raw) {
  final config = raw.clamped();
  final draft = <({TabataPhase phase, Duration duration, int cycle, int setIndex})>[];

  void add(TabataPhase phase, Duration duration, {int cycle = 0, int setIndex = 0}) {
    if (duration <= Duration.zero) return;
    draft.add((phase: phase, duration: duration, cycle: cycle, setIndex: setIndex));
  }

  add(TabataPhase.warmup, config.warmup);

  for (var set = 1; set <= config.sets; set++) {
    for (var cycle = 1; cycle <= config.cycles; cycle++) {
      add(TabataPhase.work, config.work, cycle: cycle, setIndex: set);
      final isLastWorkOverall = set == config.sets && cycle == config.cycles;
      final isLastCycleInSet = cycle == config.cycles;
      if (isLastWorkOverall) continue;
      if (!isLastCycleInSet) {
        add(TabataPhase.rest, config.rest, cycle: cycle, setIndex: set);
      }
    }
    if (set < config.sets) {
      add(TabataPhase.setRest, config.setRest, setIndex: set);
    }
  }

  add(TabataPhase.cooldown, config.cooldown);

  final total = draft.length;
  return [
    for (var i = 0; i < total; i++)
      TabataStep(
        phase: draft[i].phase,
        duration: draft[i].duration,
        cycle: draft[i].cycle,
        setIndex: draft[i].setIndex,
        totalCycles: config.cycles,
        totalSets: config.sets,
        stepIndex: i,
        totalSteps: total,
      ),
  ];
}

/// Orchestrates Tabata steps with a single [PreciseCountdown].
class TabataRunner {
  TabataRunner({required this.onChanged, this.onPhaseChanged, this.onCompleted});

  final void Function() onChanged;
  final void Function(TabataStep step)? onPhaseChanged;
  final void Function()? onCompleted;

  final PreciseCountdown _countdown = PreciseCountdown();
  List<TabataStep> _plan = const [];
  int _index = 0;
  bool _active = false;
  bool _completed = false;

  bool get isActive => _active;
  bool get isCompleted => _completed;
  bool get isRunning => _countdown.isRunning;
  bool get isPaused => _active && !_countdown.isRunning && !_completed;
  TabataStep? get currentStep => (_active && _index >= 0 && _index < _plan.length) ? _plan[_index] : null;
  int get remainingSeconds => _countdown.remainingSeconds;
  double get overallProgress {
    if (_plan.isEmpty) return 0;
    if (_completed) return 1;
    final step = currentStep;
    if (step == null) return 0;
    final stepShare = 1 / _plan.length;
    final within = step.duration.inMilliseconds <= 0
        ? 1.0
        : 1 - (_countdown.remaining.inMilliseconds / step.duration.inMilliseconds).clamp(0.0, 1.0);
    return ((step.stepIndex + within) * stepShare).clamp(0.0, 1.0);
  }

  void start(TabataConfig config) {
    disposeTickerOnly();
    _plan = buildTabataPlan(config);
    _index = 0;
    _active = true;
    _completed = false;
    _countdown
      ..onTick = onChanged
      ..onFinished = _advance;
    if (_plan.isEmpty) {
      _finish();
      return;
    }
    _beginCurrent();
  }

  void pause() {
    if (!_active || _completed) return;
    _countdown.pause();
    onChanged();
  }

  void resume() {
    if (!_active || _completed) return;
    _countdown.resume();
    onChanged();
  }

  void stop() {
    _countdown.stop();
    _active = false;
    _completed = false;
    _plan = const [];
    _index = 0;
    onChanged();
  }

  void resetToSettings() {
    stop();
  }

  void sync() => _countdown.sync();

  void dispose() {
    _countdown.dispose();
  }

  void disposeTickerOnly() {
    _countdown.stop();
  }

  void _beginCurrent() {
    while (_index < _plan.length && _plan[_index].duration <= Duration.zero) {
      _index += 1;
    }
    if (_index >= _plan.length) {
      _finish();
      return;
    }
    final step = _plan[_index];
    onPhaseChanged?.call(step);
    onChanged();
    _countdown.start(step.duration);
  }

  void _advance() {
    if (!_active || _completed) return;
    _index += 1;
    if (_index >= _plan.length) {
      _finish();
      return;
    }
    _beginCurrent();
  }

  void _finish() {
    _countdown.stop();
    _active = false;
    _completed = true;
    onChanged();
    onCompleted?.call();
  }
}
