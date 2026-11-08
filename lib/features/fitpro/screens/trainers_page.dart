import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/ru_phone.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/routes/route_names.dart';

/// Client marketplace: trainers list, bookmark, request (L12–L13).
class TrainersPage extends StatefulWidget {
  const TrainersPage({super.key});

  @override
  State<TrainersPage> createState() => _TrainersPageState();
}

class _TrainersPageState extends State<TrainersPage> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await FitApi.trainers(q: _query.text.trim());
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = int.tryParse('${item['id'] ?? item['user_id']}') ?? 0;
    if (id == 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _TrainerDetailPage(trainerId: id, preview: item)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const HubBackTitle(title: 'Найти тренера'),
          TextField(
            controller: _query,
            style: const TextStyle(color: Colors.white),
            cursorColor: AppColors.accent,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Поиск по имени',
              hintStyle: const TextStyle(color: AppColors.fitGrey),
              filled: true,
              fillColor: AppColors.fitSurface,
              suffixIcon: IconButton(onPressed: _load, icon: const Icon(Icons.search, color: AppColors.accent)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _items.isEmpty
                    ? const Center(child: Text('Тренеры не найдены', style: TextStyle(color: AppColors.fitGrey)))
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final name = _trainerName(item);
                          final rating = item['rating_avg']?.toString() ?? '—';
                          final price = _formatPrice(item['session_price_amount']);
                          final formats = _formatLabels(item['work_formats']);
                          final free = item['free_first_consult'] == true;
                          return GestureDetector(
                            onTap: () => _open(item),
                            child: HubCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                                        ),
                                      ),
                                      Text(
                                        price.isEmpty ? 'Цена не указана' : '$price ₽',
                                        style: TextStyle(
                                          color: price.isEmpty ? AppColors.fitGrey : AppColors.accent,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text('★ $rating', style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                                  if (formats.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: formats
                                          .map(
                                            (label) => Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2A2A2A),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                  if (free) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Первая встреча бесплатно',
                                      style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ],
                              ),
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

class _TrainerDetailPage extends StatefulWidget {
  const _TrainerDetailPage({required this.trainerId, required this.preview});

  final int trainerId;
  final Map<String, dynamic> preview;

  @override
  State<_TrainerDetailPage> createState() => _TrainerDetailPageState();
}

class _TrainerDetailPageState extends State<_TrainerDetailPage> {
  Map<String, dynamic> _data = const {};
  List<Map<String, dynamic>> _reviews = const [];
  bool _loading = true;
  bool _busy = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _data = widget.preview;
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await FitApi.trainerPublic(widget.trainerId);
      List<Map<String, dynamic>> reviews = const [];
      try {
        reviews = await FitApi.trainerReviews(widget.trainerId);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _data = data;
          _reviews = reviews;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _writeReview() async {
    final result = await showModalBottomSheet<({int rating, String text, bool anonymous})>(
      context: context,
      backgroundColor: AppColors.fitCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => const _TrainerReviewSheet(),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await FitApi.postTrainerReview(
        widget.trainerId,
        rating: result.rating,
        text: result.text,
        isAnonymous: result.anonymous,
      );
      if (!mounted) return;
      Toast.success('Отзыв сохранён');
      await _load();
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      final me = await FitApi.me();
      if (RuPhone.nationalDigits(me.phone).length < 10) {
        if (!mounted) return;
        Toast.error('Укажите телефон в профиле — тренер сможет связаться');
        context.push(RouteNames.account);
        return;
      }
      await FitApi.requestTrainer(widget.trainerId);
      if (!mounted) return;
      setState(() => _sent = true);
      Toast.success('Заявка отправлена');
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bookmark() async {
    setState(() => _busy = true);
    try {
      await FitApi.bookmarkTrainer(widget.trainerId);
      if (mounted) Toast.success('В закладках');
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _trainerName(_data);
    final bio = _data['bio']?.toString() ?? '';
    final price = _formatPrice(_data['session_price_amount']);
    final duration = _data['session_duration_min']?.toString() ?? '';
    final formats = _formatLabels(_data['work_formats']);
    final free = _data['free_first_consult'] == true;
    final specs = (_data['specializations'] is List)
        ? (_data['specializations'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    final rating = _data['rating_avg']?.toString() ?? '—';
    final experience = _data['experience_years']?.toString() ?? '';

    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          HubBackTitle(title: name),
          if (_loading) const LinearProgressIndicator(color: AppColors.accent, minHeight: 2),
          HubCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('★ $rating${experience.isEmpty ? '' : ' · $experience лет опыта'}', style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(bio, style: const TextStyle(color: Colors.white70, height: 1.4)),
                ],
                const SizedBox(height: 14),
                Text(
                  price.isEmpty ? 'Цена не указана' : '$price ₽ / занятие${duration.isEmpty ? '' : ' · $duration мин'}',
                  style: TextStyle(
                    color: price.isEmpty ? AppColors.fitGrey : AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Оплата напрямую тренеру, не через приложение',
                  style: TextStyle(color: AppColors.fitGrey, fontSize: 12),
                ),
                if (formats.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Формат', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: formats
                        .map(
                          (label) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (specs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Специализация', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: specs
                        .map(
                          (code) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(_specLabel(code), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (free) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Первая встреча бесплатно',
                    style: TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          FitAccentButton(
            title: _sent ? 'Заявка отправлена' : 'Оставить заявку',
            onPressed: (_busy || _sent) ? null : _request,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _bookmark,
            child: const Text('В закладки', style: TextStyle(color: AppColors.accent)),
          ),
          TextButton(
            onPressed: _busy ? null : _writeReview,
            child: const Text('Оставить отзыв', style: TextStyle(color: AppColors.accent)),
          ),
          const SizedBox(height: 16),
          const Text('Отзывы', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          if (_reviews.isEmpty)
            const Text('Пока нет отзывов', style: TextStyle(color: AppColors.fitGrey))
          else
            for (final r in _reviews)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: HubCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _reviewAuthor(r),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '★ ${r['rating'] ?? '—'}',
                            style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      if ((r['text']?.toString() ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          r['text'].toString(),
                          style: const TextStyle(color: Colors.white70, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _TrainerReviewSheet extends StatefulWidget {
  const _TrainerReviewSheet();

  @override
  State<_TrainerReviewSheet> createState() => _TrainerReviewSheetState();
}

class _TrainerReviewSheetState extends State<_TrainerReviewSheet> {
  final _textCtrl = TextEditingController();
  int _rating = 5;
  bool _anonymous = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Оставить отзыв',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: AppColors.accent,
                    size: 32,
                  ),
                ),
            ],
          ),
          TextField(
            controller: _textCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Комментарий (необязательно)',
              hintStyle: TextStyle(color: AppColors.fitGrey),
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Анонимно', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _anonymous ? 'Имя скрыто' : 'Будет видно ваше имя',
              style: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
            ),
            value: _anonymous,
            activeThumbColor: AppColors.accent,
            onChanged: (v) => setState(() => _anonymous = v),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (
                  rating: _rating,
                  text: _textCtrl.text.trim(),
                  anonymous: _anonymous,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Отправить', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

String _reviewAuthor(Map<String, dynamic> r) {
  final display = r['display_name']?.toString().trim() ?? '';
  if (display.isNotEmpty) return display;
  final full = '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
  return full.isEmpty ? 'Клиент' : full;
}

String _trainerName(Map<String, dynamic> item) {
  final name = '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim();
  return name.isEmpty ? 'Тренер' : name;
}

String _formatPrice(dynamic raw) {
  if (raw == null) return '';
  final text = raw.toString().trim();
  if (text.isEmpty || text == 'null') return '';
  final value = num.tryParse(text);
  if (value == null) return text;
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(2);
}

List<String> _formatLabels(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) => e.toString())
      .where((e) => e.isNotEmpty)
      .map(_workFormatLabel)
      .toList();
}

String _workFormatLabel(String code) {
  return switch (code) {
    'online' => 'Онлайн',
    'gym' => 'В зале',
    'home' => 'Дома',
    'visit' => 'Выезд',
    'hybrid' => 'Онлайн + офлайн',
    _ => code,
  };
}

String _specLabel(String code) {
  return switch (code) {
    'strength' => 'Сила',
    'gain_muscle' => 'Нарастить мышцы',
    'lose_weight' => 'Сбросить вес',
    'maintain' => 'Поддержание формы',
    'definition' => 'Рельеф',
    'flexibility' => 'Гибкость',
    'rehab' || 'rehabilitation' => 'Реабилитация',
    'endurance' => 'Выносливость',
    'cardio' => 'Кардио',
    'yoga' => 'Йога',
    'stretching' => 'Растяжка',
    'crossfit' => 'Кроссфит',
    'boxing' => 'Бокс',
    'pilates' => 'Пилатес',
    'nutrition' => 'Питание',
    'functional' => 'Функциональные',
    _ => code,
  };
}
