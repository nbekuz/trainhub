import 'package:flutter/material.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/date_helper.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';

/// Coach inbox for client requests — accept / reject with push to client.
class TrainerRequestsPage extends StatefulWidget {
  const TrainerRequestsPage({super.key});

  @override
  State<TrainerRequestsPage> createState() => _TrainerRequestsPageState();
}

class _TrainerRequestsPageState extends State<TrainerRequestsPage> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String _status = 'pending';
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await FitApi.trainerRequests(status: _status);
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

  Future<void> _accept(int id) async {
    setState(() => _busyId = id);
    try {
      await FitApi.acceptRequest(id);
      Toast.success('Заявка принята. Клиент получит уведомление');
      await _load();
    } catch (error) {
      Toast.error(FitApi.messageOf(error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(int id) async {
    setState(() => _busyId = id);
    try {
      await FitApi.rejectRequest(id);
      Toast.info('Заявка отклонена. Клиент получит уведомление');
      await _load();
    } catch (error) {
      Toast.error(FitApi.messageOf(error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const HubBackTitle(title: 'Заявки клиентов'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in const [
                  ('pending', 'Новые'),
                  ('accepted', 'Принятые'),
                  ('rejected', 'Отклонённые'),
                ]) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.$2),
                      selected: _status == entry.$1,
                      onSelected: (_) {
                        setState(() => _status = entry.$1);
                        _load();
                      },
                      selectedColor: AppColors.accent,
                      labelStyle: TextStyle(
                        color: _status == entry.$1 ? Colors.black : Colors.white,
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
                    ? Center(
                        child: Text(
                          _status == 'pending' ? 'Новых заявок нет' : 'Список пуст',
                          style: const TextStyle(color: AppColors.fitGrey),
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
                          final id = int.tryParse('${item['id']}') ?? 0;
                          final name =
                              '${item['first_name'] ?? item['client_first_name'] ?? ''} ${item['last_name'] ?? item['client_last_name'] ?? ''}'
                                  .trim();
                          final phone = item['phone']?.toString() ?? '';
                          final email = item['email']?.toString() ?? '';
                          final created = DateHelper.formatRuShortAny(item['created_at']);
                          final pending = item['status']?.toString() == 'pending' || _status == 'pending';
                          final busy = _busyId == id;
                          return HubCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? 'Клиент' : name,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(phone, style: const TextStyle(color: AppColors.fitGrey)),
                                ],
                                if (email.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(email, style: const TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                                ],
                                if (created.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(created, style: const TextStyle(color: Color(0xFF7A7A7A), fontSize: 12)),
                                ],
                                if (pending) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: (id == 0 || busy) ? null : () => _accept(id),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.accent,
                                            foregroundColor: Colors.black,
                                          ),
                                          child: Text(busy ? '…' : 'Принять'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: (id == 0 || busy) ? null : () => _reject(id),
                                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF6B6B)),
                                          child: const Text('Отклонить'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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
