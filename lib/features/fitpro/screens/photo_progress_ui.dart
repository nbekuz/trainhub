import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/utils/date_helper.dart';
import 'package:trainhub/core/utils/image_upload.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/fit_cache.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';

const _lime = Color(0xFFC4F52B);
const _card = Color(0xFF232323);
const _inner = Color(0xFF292929);
const _border = Color(0xFF323232);
const _label = Color(0xFFA0A0A0);

const _angles = <({String code, String title})>[
  (code: 'front', title: 'Фронт'),
  (code: 'side', title: 'Бок'),
  (code: 'back', title: 'Спина'),
];

String _relativeLabel(DateTime? at) {
  if (at == null) return 'Фотосет';
  final days = DateTime.now().difference(at).inDays;
  if (days < 7) return 'На этой неделе';
  if (days < 35) return '1 месяц назад';
  final months = (days / 30).round().clamp(1, 120);
  if (months == 1) return '1 месяц назад';
  if (months >= 2 && months <= 4) return '$months месяца назад';
  return '$months месяцев назад';
}

List<String> _imageUrls(Map<String, dynamic> set) {
  final images = set['images'];
  final urls = <String>[];
  if (images is List) {
    // Prefer front → side → back order when angles present.
    final byAngle = <String, String>{};
    final ordered = <String>[];
    for (final item in images.whereType<Map>()) {
      final url = item['image_url']?.toString() ?? item['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      final angle = item['angle']?.toString() ?? '';
      if (angle.isNotEmpty) {
        byAngle[angle] = url;
      } else {
        ordered.add(url);
      }
    }
    for (final a in _angles) {
      final url = byAngle[a.code];
      if (url != null) urls.add(url);
    }
    for (final url in ordered) {
      if (!urls.contains(url)) urls.add(url);
    }
    for (final entry in byAngle.entries) {
      if (!_angles.any((a) => a.code == entry.key) && !urls.contains(entry.value)) {
        urls.add(entry.value);
      }
    }
  }
  return urls;
}

class PhotoProgressPage extends StatefulWidget {
  const PhotoProgressPage({super.key});

  @override
  State<PhotoProgressPage> createState() => _PhotoProgressPageState();
}

class _PhotoProgressPageState extends State<PhotoProgressPage> {
  List<Map<String, dynamic>> _sets = const [];
  StreamSubscription<String>? _cacheSub;

  @override
  void initState() {
    super.initState();
    final cached = FitCache.I.peek<List<Map<String, dynamic>>>('photo-progress');
    if (cached != null) _applySets(cached);
    _cacheSub = FitCache.I.updates.listen((key) {
      if (key != 'photo-progress' || !mounted) return;
      final next = FitCache.I.peek<List<Map<String, dynamic>>>('photo-progress');
      if (next != null) _applySets(next);
    });
    _load();
  }

  @override
  void dispose() {
    _cacheSub?.cancel();
    super.dispose();
  }

  void _applySets(List<Map<String, dynamic>> sets) {
    final sorted = [...sets]..sort((a, b) {
        final aa = DateTime.tryParse(a['taken_on']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bb = DateTime.tryParse(b['taken_on']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bb.compareTo(aa);
      });
    setState(() => _sets = sorted);
  }

  Future<void> _load({bool force = false}) async {
    try {
      final sets = await FitApi.photoProgress(force: force);
      if (!mounted) return;
      _applySets(sets);
    } catch (_) {
      // silent
    }
  }

  Future<void> _add() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CreatePhotoSetSheet(),
    );
    if (created == true) await _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          HubBackTitle(
            title: 'Фото прогресс',
            trailing: GestureDetector(
              onTap: _add,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: _lime, shape: BoxShape.circle),
                child: const Icon(Icons.add, color: Colors.black, size: 22),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border),
            ),
            child: _sets.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      children: [
                        Text('Фото пока нет', style: GoogleFonts.openSans(color: Colors.white, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(
                          'Добавьте 3 фото: фронт, бок и спина',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.openSans(color: _label, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: _add,
                          style: TextButton.styleFrom(foregroundColor: _lime),
                          icon: const Icon(Icons.add),
                          label: const Text('Добавить фотосет'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < _sets.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _PhotoSetCard(set: _sets[i]),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PhotoSetCard extends StatelessWidget {
  const _PhotoSetCard({required this.set});

  final Map<String, dynamic> set;

  @override
  Widget build(BuildContext context) {
    final takenOn = DateHelper.parseLocal(set['taken_on']?.toString());
    final label = _relativeLabel(takenOn);
    final date = takenOn == null ? '' : DateHelper.formatRuDate(takenOn);
    final urls = _imageUrls(set);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _inner,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: label,
                  style: GoogleFonts.openSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (date.isNotEmpty)
                  TextSpan(
                    text: ' ($date)',
                    style: GoogleFonts.openSans(color: _label, fontSize: 13),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 0.85,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: i < urls.length
                          ? Image.network(
                              urls[i],
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stackTrace) => const ColoredBox(
                                color: Color(0xFF1C1C1C),
                                child: Icon(Icons.photo, color: _label),
                              ),
                            )
                          : const ColoredBox(
                              color: Color(0xFF1C1C1C),
                              child: Icon(Icons.image_outlined, color: _label),
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CreatePhotoSetSheet extends StatefulWidget {
  const _CreatePhotoSetSheet();

  @override
  State<_CreatePhotoSetSheet> createState() => _CreatePhotoSetSheetState();
}

class _CreatePhotoSetSheetState extends State<_CreatePhotoSetSheet> {
  final _paths = <String?>[null, null, null];
  DateTime _takenOn = DateTime.now();
  bool _saving = false;

  bool get _ready => _paths.every((p) => p != null && p.isNotEmpty);

  Future<void> _pick(int index) async {
    try {
      final prepared = await pickPreparedImage();
      if (prepared == null) return;
      setState(() => _paths[index] = prepared.path);
    } catch (e) {
      Toast.error(e is FormatException ? e.message : FitApi.messageOf(e));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _takenOn,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(primary: _lime, onPrimary: Colors.black, surface: Color(0xFF1C1C1C)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _takenOn = picked);
  }

  Future<void> _save() async {
    if (!_ready) {
      Toast.info('Добавьте 3 фото: фронт, бок и спина');
      return;
    }
    setState(() => _saving = true);
    try {
      await FitApi.uploadPhotoProgress(
        takenOn: DateFormat('yyyy-MM-dd').format(_takenOn),
        filePaths: [for (final p in _paths) p!],
        angles: [for (final a in _angles) a.code],
      );
      if (!mounted) return;
      Toast.success('Фотосет сохранён');
      Navigator.pop(context, true);
    } catch (error) {
      Toast.error(FitApi.messageOf(error));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.12),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: const Color(0xFF3A3A3A), borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Новый фотосет',
              style: GoogleFonts.openSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'За один раз загружаются 3 фото',
              style: GoogleFonts.openSans(color: _label, fontSize: 13),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, color: _label, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    DateHelper.formatRuDate(_takenOn),
                    style: GoogleFonts.openSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _AngleSlot(title: _angles[i].title, path: _paths[i], onTap: () => _pick(i))),
              ],
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: _border),
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _lime,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF3A3A3A),
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AngleSlot extends StatelessWidget {
  const _AngleSlot({required this.title, required this.path, required this.onTap});

  final String title;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = path != null;
    const radius = 14.0;
    const borderW = 1.5;
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 0.85,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? _lime : _border,
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Padding(
                // Border as outer fill + inset — image can't clip/cover the stroke.
                padding: const EdgeInsets.all(borderW),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius - borderW),
                  child: ColoredBox(
                    color: _card,
                    child: !selected
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_a_photo_outlined, color: _label, size: 26),
                              const SizedBox(height: 6),
                              Text('Выбрать', style: GoogleFonts.openSans(color: _label, fontSize: 11)),
                            ],
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(File(path!), fit: BoxFit.cover),
                              const Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.check_circle, color: _lime, size: 20),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(title, style: GoogleFonts.openSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
