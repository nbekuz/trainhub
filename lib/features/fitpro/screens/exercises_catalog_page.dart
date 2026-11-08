import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/fit_labels.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/routes/route_names.dart';

/// Exercise catalog + create (not in Figma; matches Hub UI).
class ExercisesCatalogPage extends StatefulWidget {
  const ExercisesCatalogPage({super.key});

  @override
  State<ExercisesCatalogPage> createState() => _ExercisesCatalogPageState();
}

class _ExercisesCatalogPageState extends State<ExercisesCatalogPage> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _muscle;
  String? _equipment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await FitApi.exercises(
        q: _q.text.trim().isEmpty ? null : _q.text.trim(),
        muscle: _muscle,
        equipment: _equipment,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          HubBackTitle(
            title: 'Упражнения',
            trailing: TextButton(
              onPressed: () async {
                await context.push(RouteNames.createExercise);
                if (mounted) _load();
              },
              child: const Text('Создать', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
            ),
          ),
          TextField(
            controller: _q,
            onSubmitted: (_) => _load(),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Поиск упражнения',
              hintStyle: const TextStyle(color: AppColors.fitGrey),
              prefixIcon: const Icon(Icons.search, color: AppColors.fitGrey),
              suffixIcon: IconButton(
                onPressed: _load,
                icon: const Icon(Icons.tune, color: Colors.white70),
              ),
              filled: true,
              fillColor: AppColors.fitCard,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.accent,
              onRefresh: _load,
              child: _loading
                  ? ListView(children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator(color: AppColors.accent))])
                  : _items.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 80),
                            HubCard(
                              child: Column(
                                children: [
                                  const Text('Упражнений не найдено', style: TextStyle(color: AppColors.fitGrey)),
                                  TextButton(
                                    onPressed: () => context.push(RouteNames.createExercise),
                                    child: const Text('Создать своё', style: TextStyle(color: AppColors.accent)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 40),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            final title = item['title']?.toString() ?? item['name']?.toString() ?? 'Упражнение';
                            final muscle = FitLabels.muscle(
                              item['primary_muscle']?.toString() ??
                                  item['focus_muscle']?.toString() ??
                                  item['muscle']?.toString(),
                            );
                            final equipmentRaw = item['equipment'];
                            final equipment = equipmentRaw is List
                                ? equipmentRaw
                                    .map((e) => FitLabels.equipment(e?.toString()))
                                    .where((e) => e.isNotEmpty)
                                    .join(', ')
                                : FitLabels.equipment(equipmentRaw?.toString());
                            return Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C2C2C),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  FitExerciseThumb.fromExercise(item, size: 56),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(
                                          [if (muscle.isNotEmpty) muscle, if (equipment.isNotEmpty) equipment].join(' · '),
                                          style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (item['has_video'] == true || (item['video_url']?.toString().isNotEmpty ?? false))
                                    const Icon(Icons.play_circle_outline, color: AppColors.accent),
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
