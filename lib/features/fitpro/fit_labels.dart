/// Shared RU labels for FitPro dictionary codes shown in UI.
class FitLabels {
  FitLabels._();

  static String kind(String? code) {
    final raw = (code ?? '').trim();
    if (raw.isEmpty) return '';
    return switch (raw.toLowerCase()) {
      'strength' => 'Силовая',
      'cardio' => 'Кардио',
      'stretch' || 'stretching' || 'flexibility' => 'Растяжка',
      'run' || 'running' => 'Бег',
      'yoga' => 'Йога',
      'hiit' => 'HIIT',
      'functional' => 'Функциональная',
      'rehab' || 'rehabilitation' || 'recovery' => 'Реабилитация',
      _ => raw,
    };
  }

  static String kinds(Object? value) {
    if (value is List) {
      final parts = value
          .map((e) => kind(e?.toString()))
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isEmpty) return 'Тренировка';
      return parts.join(', ');
    }
    final single = kind(value?.toString());
    return single.isEmpty ? 'Тренировка' : single;
  }

  /// Prefer human title; translate dictionary codes like `strength`.
  static String workoutTitle(Map<String, dynamic> item, {String fallback = 'Тренировка'}) {
    final rawTitle = item['title']?.toString().trim() ?? '';
    final kindCodes = item['kinds'] ?? item['kind'];
    if (rawTitle.isEmpty) return kinds(kindCodes).isEmpty ? fallback : kinds(kindCodes);

    final lower = rawTitle.toLowerCase();
    final translated = kind(rawTitle);
    final isCode = translated != rawTitle ||
        const {
          'strength',
          'cardio',
          'stretch',
          'stretching',
          'flexibility',
          'run',
          'running',
          'yoga',
          'hiit',
          'functional',
          'rehab',
        }.contains(lower);
    if (isCode && translated.isNotEmpty) return translated;
    return rawTitle;
  }

  static String sessionStatus(String? status) {
    return switch (status) {
      'completed' => 'Завершено',
      'in_progress' => 'В процессе',
      'cancelled' => 'Отменено',
      'no_show' => 'Неявка',
      _ => 'Ожидает',
    };
  }

  static String muscle(String? code) {
    final raw = (code ?? '').trim();
    if (raw.isEmpty) return '';
    return switch (raw.toLowerCase()) {
      'chest' => 'Грудь',
      'legs' || 'thighs' => 'Ноги',
      'back' => 'Спина',
      'press' || 'abs' || 'waist' => 'Пресс',
      'arms' || 'biceps' || 'triceps' => 'Руки',
      'shoulders' || 'delts' => 'Плечи',
      'glutes' => 'Ягодицы',
      'traps' => 'Трапеции',
      'full_body' || 'other' => 'Всё тело',
      'neck' => 'Шея',
      'calves' => 'Икры',
      'forearms' => 'Предплечья',
      _ => raw,
    };
  }

  static String equipment(String? code) {
    final raw = (code ?? '').trim();
    if (raw.isEmpty) return '';
    return switch (raw.toLowerCase()) {
      'bodyweight' || 'none' => 'Свой вес',
      'barbell' => 'Штанга',
      'dumbbell' || 'dumbbells' => 'Гантели',
      'cable' => 'Блок',
      'machine' => 'Тренажёр',
      'kettlebell' => 'Гиря',
      'plate' => 'Диск',
      'bench' => 'Скамья',
      'gym' => 'Тренажёрный зал',
      'other' => 'Другое',
      _ => raw,
    };
  }
}
