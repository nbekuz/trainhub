import 'package:flutter/material.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/date_helper.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';

/// Client view of their requests to trainers (pending / accepted / rejected).
class MyTrainerRequestsPage extends StatefulWidget {
  const MyTrainerRequestsPage({super.key});

  @override
  State<MyTrainerRequestsPage> createState() => _MyTrainerRequestsPageState();
}

class _MyTrainerRequestsPageState extends State<MyTrainerRequestsPage> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await FitApi.myTrainerRequests(status: _filter);
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

  String _statusLabel(String? status) {
    return switch (status) {
      'pending' => 'Ожидает',
      'accepted' => 'Принята',
      'rejected' => 'Отклонена',
      _ => status ?? '—',
    };
  }

  Color _statusColor(String? status) {
    return switch (status) {
      'pending' => const Color(0xFFFFB020),
      'accepted' => AppColors.accent,
      'rejected' => const Color(0xFFFF6B6B),
      _ => AppColors.fitGrey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const HubBackTitle(title: 'Мои заявки'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in const [
                  (null, 'Все'),
                  ('pending', 'Ожидают'),
                  ('accepted', 'Приняты'),
                  ('rejected', 'Отклонены'),
                ]) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.$2),
                      selected: _filter == entry.$1,
                      onSelected: (_) {
                        setState(() => _filter = entry.$1);
                        _load();
                      },
                      selectedColor: AppColors.accent,
                      labelStyle: TextStyle(
                        color: _filter == entry.$1 ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: const Color(0xFF232323),
                      side: const BorderSide(color: Color(0xFF323232)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _items.isEmpty
                    ? const Center(
                        child: Text(
                          'Заявок пока нет.\nНайдите тренера и отправьте заявку.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.fitGrey),
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.accent,
                        onRefresh: _load,
                        child: ListView.separated(
                        physics: fitAlwaysScroll,
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final name =
                              '${item['trainer_first_name'] ?? ''} ${item['trainer_last_name'] ?? ''}'.trim();
                          final status = item['status']?.toString();
                          final created = DateHelper.formatRuShortAny(item['created_at']);
                          return HubCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.isEmpty ? 'Тренер' : name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (created.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(created, style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _statusLabel(status),
                                    style: TextStyle(
                                      color: _statusColor(status),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
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
