import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/date_helper.dart';
import 'package:trainhub/core/utils/image_upload.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/features/fitpro/widgets/hub_ui.dart';
import 'package:trainhub/routes/route_names.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

final _youtubeIdRe = RegExp(
  r'(?:youtube\.com/(?:watch\?(?:[^#]*&)?v=|embed/|shorts/|live/)|youtu\.be/)([A-Za-z0-9_-]{11})',
);

String? youtubeVideoId(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  return _youtubeIdRe.firstMatch(url.trim())?.group(1);
}

String? youtubeThumbnailUrl(String? url) {
  final id = youtubeVideoId(url);
  return id == null ? null : 'https://img.youtube.com/vi/$id/hqdefault.jpg';
}

bool isYoutubeUrl(String? url) => youtubeVideoId(url) != null;

String _videoLevel(String? raw) => switch (raw) {
      'beginner' => 'Начальный',
      'intermediate' => 'Средний',
      'advanced' => 'Продвинутый',
      _ => raw?.isNotEmpty == true ? raw! : '—',
    };

String _videoStatus(String? raw) => switch (raw) {
      'draft' => 'Черновик',
      'processing' => 'Обработка',
      'pending_review' => 'На модерации',
      'published' => 'Опубликовано',
      'rejected' => 'Отклонено',
      'archived' => 'Архив',
      _ => raw ?? '—',
    };

String _durationLabel(Object? seconds) {
  final total = int.tryParse('$seconds') ?? 0;
  if (total <= 0) return '';
  final m = total ~/ 60;
  final s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _trainerName(Map<String, dynamic> video) {
  final trainer = video['trainer'];
  if (trainer is Map) {
    final name = '${trainer['first_name'] ?? ''} ${trainer['last_name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
  }
  return video['trainer_name']?.toString() ?? '';
}

// ─── Catalog hub ──────────────────────────────────────────────────────────────

class VideoCatalogPage extends ConsumerStatefulWidget {
  const VideoCatalogPage({super.key});

  @override
  ConsumerState<VideoCatalogPage> createState() => _VideoCatalogPageState();
}

class _VideoCatalogPageState extends ConsumerState<VideoCatalogPage> {
  List<Map<String, dynamic>> _categories = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await FitApi.videoCategories();
      if (!mounted) return;
      setState(() {
        _categories = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trainer = ref.watch(fitSessionProvider).user?.role == FitRole.trainer;
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const HubBackTitle(title: 'Видеоуроки'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : RefreshIndicator(
                    color: AppColors.accent,
                    onRefresh: _load,
                    child: ListView(
                      children: [
                        HubCard(
                          child: Column(
                            children: [
                              if (trainer)
                                HubMenuTile(
                                  icon: Icons.video_library_outlined,
                                  label: 'Мои видео',
                                  onTap: () => context.push(RouteNames.myVideos),
                                ),
                              if (!trainer)
                                HubMenuTile(
                                  icon: Icons.assignment_ind_outlined,
                                  label: 'Назначено тренером (видео и курсы)',
                                  onTap: () => context.push(RouteNames.assignedVideos),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Категории', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 10),
                        if (_categories.isEmpty)
                          const Text('Категорий пока нет — их создаёт админ в панели', style: TextStyle(color: AppColors.fitGrey))
                        else
                          for (final item in _categories)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: GestureDetector(
                                onTap: () {
                                  final id = int.tryParse('${item['id']}') ?? 0;
                                  if (id == 0) return;
                                  context.push(RouteNames.videoTopics, extra: {
                                    'id': id,
                                    'title': item['name']?.toString() ?? item['title']?.toString() ?? 'Категория',
                                  });
                                },
                                child: Container(
                                  height: 88,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF232323),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFF323232)),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 88,
                                        height: 88,
                                        child: () {
                                          final thumb = item['thumbnail_url']?.toString();
                                          if (thumb != null && thumb.isNotEmpty) {
                                            return Image.network(
                                              thumb,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) => const ColoredBox(
                                                color: Color(0xFF1A1A1A),
                                                child: Icon(Icons.play_circle_outline, color: AppColors.accent, size: 32),
                                              ),
                                            );
                                          }
                                          return const ColoredBox(
                                            color: Color(0xFF1A1A1A),
                                            child: Icon(Icons.play_circle_outline, color: AppColors.accent, size: 32),
                                          );
                                        }(),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                item['name']?.toString() ?? item['title']?.toString() ?? 'Категория',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${item['topics_count'] ?? 0} тем · ${item['videos_count'] ?? 0} видео',
                                                style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.only(right: 12),
                                        child: Icon(Icons.chevron_right, color: Colors.white54),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class VideoTopicsPage extends StatefulWidget {
  const VideoTopicsPage({super.key, required this.categoryId, required this.title});

  final int categoryId;
  final String title;

  @override
  State<VideoTopicsPage> createState() => _VideoTopicsPageState();
}

class _VideoTopicsPageState extends State<VideoTopicsPage> {
  List<Map<String, dynamic>> _topics = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await FitApi.categoryTopics(widget.categoryId);
      if (!mounted) return;
      setState(() {
        _topics = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          HubBackTitle(title: widget.title),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _topics.isEmpty
                    ? const Center(child: Text('Тем пока нет', style: TextStyle(color: AppColors.fitGrey)))
                    : ListView.separated(
                        itemCount: _topics.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _topics[index];
                          final id = int.tryParse('${item['id']}') ?? 0;
                          return GestureDetector(
                            onTap: () {
                              if (id == 0) return;
                              context.push(RouteNames.topicVideos, extra: {
                                'id': id,
                                'title': item['name']?.toString() ?? item['title']?.toString() ?? 'Тема',
                              });
                            },
                            child: HubCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item['name']?.toString() ?? item['title']?.toString() ?? 'Тема',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Text(
                                    '${item['videos_count'] ?? ''}',
                                    style: const TextStyle(color: AppColors.fitGrey),
                                  ),
                                  const Icon(Icons.chevron_right, color: Colors.white54),
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

class TopicVideosPage extends StatefulWidget {
  const TopicVideosPage({super.key, required this.topicId, required this.title});

  final int topicId;
  final String title;

  @override
  State<TopicVideosPage> createState() => _TopicVideosPageState();
}

class _TopicVideosPageState extends State<TopicVideosPage> {
  List<Map<String, dynamic>> _videos = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await FitApi.topicVideos(widget.topicId);
      if (!mounted) return;
      setState(() {
        _videos = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          HubBackTitle(title: widget.title),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _videos.isEmpty
                    ? const Center(child: Text('Роликов пока нет', style: TextStyle(color: AppColors.fitGrey)))
                    : ListView.separated(
                        itemCount: _videos.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _VideoTile(
                          video: _videos[index],
                          onTap: () {
                            final id = int.tryParse('${_videos[index]['id']}') ?? 0;
                            if (id == 0) return;
                            context.push(RouteNames.videoPlayer, extra: id);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video, required this.onTap, this.trailing});

  final Map<String, dynamic> video;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final title = video['title']?.toString() ?? 'Видео';
    final thumbRaw = video['thumbnail_url']?.toString() ?? '';
    final thumb = thumbRaw.isNotEmpty ? thumbRaw : (youtubeThumbnailUrl(video['video_url']?.toString()) ?? '');
    final author = _trainerName(video);
    final duration = _durationLabel(video['duration_seconds']);
    final level = _videoLevel(video['level']?.toString());
    return GestureDetector(
      onTap: onTap,
      child: HubCard(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
              child: SizedBox(
                width: 110,
                height: 88,
                child: thumb.isEmpty
                    ? const ColoredBox(color: Color(0xFF222222), child: Icon(Icons.play_circle_outline, color: AppColors.accent, size: 36))
                    : Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF222222), child: Icon(Icons.broken_image, color: Colors.white38))),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      [if (author.isNotEmpty) author, level, if (duration.isNotEmpty) duration].join(' · '),
                      style: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            if (trailing != null) trailing!,
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Player ───────────────────────────────────────────────────────────────────

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.videoId, this.assignmentId});

  final int videoId;
  final int? assignmentId;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  Map<String, dynamic> _video = const {};
  VideoPlayerController? _controller;
  WebViewController? _youtubeController;
  bool _loading = true;
  String? _error;
  bool _isYoutube = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  WebViewController _buildYoutubeWebView(String videoId) {
    final embed = 'https://www.youtube.com/embed/$videoId?playsinline=1&rel=0&modestbranding=1';
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            // Keep playback inside the app WebView — block YouTube app / external browser.
            if (url.startsWith('https://www.youtube.com/embed/') ||
                url.startsWith('https://www.youtube-nocookie.com/embed/') ||
                url.contains('youtube.com/embed/') ||
                url.contains('youtube-nocookie.com/embed/') ||
                url.contains('googlevideo.com') ||
                url.contains('ytimg.com') ||
                url.startsWith('about:blank') ||
                url == embed) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(embed));
  }

  Future<void> _load() async {
    try {
      Map<String, dynamic> data;
      if (widget.assignmentId != null) {
        final assignment = await FitApi.myAssignedVideo(widget.assignmentId!);
        data = assignment['video'] is Map ? Map<String, dynamic>.from(assignment['video'] as Map) : assignment;
      } else {
        try {
          data = await FitApi.video(widget.videoId);
        } catch (_) {
          data = await FitApi.myAccessibleVideo(widget.videoId);
        }
      }
      final url = data['video_url']?.toString();
      final ytId = youtubeVideoId(url);
      final hasVideo = data['has_video'] != false && url != null && url.isNotEmpty;
      if (!mounted) return;
      setState(() {
        _video = data;
        _loading = false;
        _isYoutube = ytId != null;
        if (!hasVideo) _error = 'Видео недоступно';
      });
      if (!hasVideo) return;
      if (ytId != null) {
        setState(() => _youtubeController = _buildYoutubeWebView(ytId));
        return;
      }
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = FitApi.messageOf(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _video['exercise_details'];
    final detailsMap = details is Map ? Map<String, dynamic>.from(details) : const <String, dynamic>{};
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          HubBackTitle(title: _video['title']?.toString() ?? 'Видео'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
            )
          else ...[
            AspectRatio(
              aspectRatio: _isYoutube
                  ? 16 / 9
                  : (_controller?.value.aspectRatio == 0 ? 16 / 9 : (_controller?.value.aspectRatio ?? 16 / 9)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ColoredBox(
                  color: Colors.black,
                  child: _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.fitGrey)))
                      : _isYoutube
                          ? (_youtubeController == null
                              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                              : WebViewWidget(controller: _youtubeController!))
                          : _controller == null
                              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                              : Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    VideoPlayer(_controller!),
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          if (_controller!.value.isPlaying) {
                                            _controller!.pause();
                                          } else {
                                            _controller!.play();
                                          }
                                        });
                                      },
                                      icon: Icon(
                                        _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                        color: AppColors.accent,
                                        size: 64,
                                      ),
                                    ),
                                  ],
                                ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(_video['title']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              [
                if (_trainerName(_video).isNotEmpty) _trainerName(_video),
                if ((_video['category_name']?.toString() ?? '').isNotEmpty) _video['category_name'],
                if ((_video['topic_name']?.toString() ?? '').isNotEmpty) _video['topic_name'],
                _videoLevel(_video['level']?.toString()),
                _durationLabel(_video['duration_seconds']),
              ].where((item) => '$item'.isNotEmpty).join(' · '),
              style: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
            ),
            if ((_video['description']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(_video['description'].toString(), style: const TextStyle(color: Colors.white70, height: 1.4)),
            ],
            if (detailsMap.isNotEmpty) ...[
              const SizedBox(height: 16),
              HubCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Детали упражнения', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final key in ['technique', 'equipment', 'muscles', 'sets', 'reps'])
                      if ((detailsMap[key]?.toString() ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('${_detailLabel(key)}: ${detailsMap[key]}', style: const TextStyle(color: AppColors.fitGrey)),
                        ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ],
      ),
    );
  }

  String _detailLabel(String key) => switch (key) {
        'technique' => 'Техника',
        'equipment' => 'Инвентарь',
        'muscles' => 'Мышцы',
        'sets' => 'Подходы',
        'reps' => 'Повторы',
        _ => key,
      };
}

// ─── Coach: my videos ─────────────────────────────────────────────────────────

class MyVideosPage extends StatefulWidget {
  const MyVideosPage({super.key});

  @override
  State<MyVideosPage> createState() => _MyVideosPageState();
}

class _MyVideosPageState extends State<MyVideosPage> {
  static const _filters = <(String?, String)>[
    (null, 'Все'),
    ('draft', 'Черновик'),
    ('pending_review', 'На модерации'),
    ('published', 'Опубликовано'),
    ('rejected', 'Отклонено'),
  ];

  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  String? _status;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((v) {
      final title = v['title']?.toString().toLowerCase() ?? '';
      final cat = v['category_name']?.toString().toLowerCase() ?? '';
      final topic = v['topic_name']?.toString().toLowerCase() ?? '';
      return title.contains(q) || cat.contains(q) || topic.contains(q);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await FitApi.myTrainerVideos(status: _status);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = FitApi.messageOf(error);
      });
    }
  }

  Future<void> _create() async {
    final created = await context.push<bool>(RouteNames.videoCreate);
    if (created == true && mounted) _load();
  }

  Future<void> _edit(Map<String, dynamic> video) async {
    final updated = await context.push<bool>(RouteNames.videoCreate, extra: video);
    if (updated == true && mounted) _load();
  }

  Future<void> _submit(int id, {required bool resubmit}) async {
    try {
      await FitApi.submitTrainerVideo(id);
      if (!mounted) return;
      Toast.success(resubmit ? 'Повторно отправлено на модерацию' : 'Отправлено на модерацию');
      _load();
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _archive(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.fitCard,
        title: const Text('Удалить видео?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Видео будет архивировано и исчезнет из вашей библиотеки.',
          style: TextStyle(color: AppColors.fitGrey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Color(0xFFFD6565))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FitApi.deleteTrainerVideo(id);
      if (!mounted) return;
      Toast.info('Видео удалено');
      _load();
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _showRejection(String reason) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.fitCard,
        title: const Text('Причина отклонения', style: TextStyle(color: Colors.white)),
        content: Text(reason, style: const TextStyle(color: AppColors.fitGrey, height: 1.35)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> _assignToClient(Map<String, dynamic> video) async {
    final videoId = int.tryParse('${video['id']}') ?? 0;
    if (videoId == 0) return;
    List clients = const [];
    try {
      clients = await FitApi.trainerClients();
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
      return;
    }
    if (!mounted) return;
    if (clients.isEmpty) {
      Toast.info('Клиентов пока нет');
      return;
    }
    final linkId = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.fitCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Назначить видео клиенту', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          for (final c in clients)
            ListTile(
              title: Text('${c.name} ${c.surname}'.trim(), style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, c.id as int),
            ),
        ],
      ),
    );
    if (linkId == null) return;
    try {
      await FitApi.assignVideosToClient(linkId, [videoId]);
      if (mounted) Toast.success('Видео назначено');
    } catch (e) {
      if (mounted) Toast.error(FitApi.messageOf(e));
    }
  }

  String get _emptyTitle {
    return switch (_status) {
      'draft' => 'Нет черновиков',
      'pending_review' => 'Нет видео на модерации',
      'published' => 'Нет опубликованных видео',
      'rejected' => 'Нет отклонённых видео',
      _ => 'Пока нет видео',
    };
  }

  String get _emptySubtitle {
    return switch (_status) {
      'draft' => 'Сохраните ролик в библиотеку — он появится здесь',
      'pending_review' => 'Отправьте черновик на проверку из меню видео',
      'published' => 'Опубликованные ролики появятся после модерации',
      'rejected' => 'Отклонённые ролики будут показаны здесь',
      _ => 'Добавьте YouTube-ссылку или файл в личную библиотеку',
    };
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          HubBackTitle(
            title: 'Мои видео',
            trailing: IconButton(
              onPressed: _create,
              icon: const Icon(Icons.add_circle_outline, color: AppColors.accent),
            ),
          ),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              hintText: 'Поиск по названию, категории, теме',
              hintStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: AppColors.fitGrey),
              filled: true,
              fillColor: const Color(0xFF1C1C1C),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final item = _filters[i];
                final selected = _status == item.$1;
                return ChoiceChip(
                  label: Text(item.$2),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) {
                    if (_status == item.$1) return;
                    setState(() => _status = item.$1);
                    _load();
                  },
                  selectedColor: AppColors.accent,
                  labelStyle: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  backgroundColor: const Color(0xFF232323),
                  side: BorderSide(color: selected ? AppColors.accent : const Color(0xFF3A3A3A)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.accent,
              onRefresh: _load,
              child: _loading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator(color: AppColors.accent)),
                      ],
                    )
                  : _error != null
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          children: [
                            const SizedBox(height: 80),
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.fitGrey)),
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: _load,
                                child: const Text('Повторить', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        )
                      : _visible.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              children: [
                                const SizedBox(height: 72),
                                Text(_emptyTitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                Text(_emptySubtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.fitGrey, height: 1.35)),
                                const SizedBox(height: 20),
                                Center(
                                  child: FilledButton(
                                    onPressed: _create,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: const Text('Добавить видео', style: TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 120),
                              itemCount: _visible.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = _visible[index];
                                final id = int.tryParse('${item['id']}') ?? 0;
                                final status = item['status']?.toString() ?? '';
                                final reason = item['rejection_reason']?.toString().trim() ?? '';
                                return _MyVideoCard(
                                  video: item,
                                  onOpen: id == 0 ? null : () => context.push(RouteNames.videoPlayer, extra: id),
                                  onEdit: id == 0 ? null : () => _edit(item),
                                  onSubmit: (status == 'draft' || status == 'rejected') && id != 0
                                      ? () => _submit(id, resubmit: status == 'rejected')
                                      : null,
                                  onShowReason: status == 'rejected' && reason.isNotEmpty ? () => _showRejection(reason) : null,
                                  onAssign: id == 0 ? null : () => _assignToClient(item),
                                  onDelete: id == 0 ? null : () => _archive(id),
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

class _MyVideoCard extends StatelessWidget {
  const _MyVideoCard({
    required this.video,
    this.onOpen,
    this.onEdit,
    this.onSubmit,
    this.onShowReason,
    this.onAssign,
    this.onDelete,
  });

  final Map<String, dynamic> video;
  final VoidCallback? onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onSubmit;
  final VoidCallback? onShowReason;
  final VoidCallback? onAssign;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final title = video['title']?.toString().trim().isNotEmpty == true ? video['title'].toString() : 'Без названия';
    final description = video['description']?.toString().trim() ?? '';
    final status = video['status']?.toString() ?? '';
    final category = video['category_name']?.toString() ?? '';
    final topic = video['topic_name']?.toString() ?? '';
    final level = _videoLevel(video['level']?.toString());
    final thumbRaw = video['thumbnail_url']?.toString() ?? '';
    final thumb = thumbRaw.isNotEmpty ? thumbRaw : (youtubeThumbnailUrl(video['video_url']?.toString()) ?? '');
    final meta = [
      if (category.isNotEmpty) category,
      if (topic.isNotEmpty) topic,
      if (level != '—') level,
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2E2E2E)),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 104,
                  height: 58,
                  child: thumb.isEmpty
                      ? const ColoredBox(
                          color: Color(0xFF2A2A2A),
                          child: Center(child: Icon(Icons.play_circle_outline, color: AppColors.accent, size: 28)),
                        )
                      : Image.network(
                          thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0xFF2A2A2A),
                            child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 22)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.3)),
                    ],
                    const SizedBox(height: 8),
                    _StatusBadge(status: status),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                color: AppColors.fitCard,
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, color: Colors.white70, size: 22),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit?.call();
                    case 'submit':
                      onSubmit?.call();
                    case 'reason':
                      onShowReason?.call();
                    case 'assign':
                      onAssign?.call();
                    case 'delete':
                      onDelete?.call();
                  }
                },
                itemBuilder: (_) => [
                  if (onEdit != null) const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                  if (onSubmit != null)
                    PopupMenuItem(
                      value: 'submit',
                      child: Text(status == 'rejected' ? 'Повторно отправить' : 'Отправить на модерацию'),
                    ),
                  if (onAssign != null) const PopupMenuItem(value: 'assign', child: Text('Назначить клиенту')),
                  if (onShowReason != null) const PopupMenuItem(value: 'reason', child: Text('Причина отклонения')),
                  if (onDelete != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Удалить', style: TextStyle(color: Color(0xFFFD6565))),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      'draft' => ('Черновик', const Color(0xFFB0B0B0), const Color(0xFF2A2A2A)),
      'pending_review' => ('На модерации', const Color(0xFFFFC857), const Color(0x33FFC857)),
      'published' => ('Опубликовано', AppColors.accent, AppColors.accent.withValues(alpha: 0.16)),
      'rejected' => ('Отклонено', const Color(0xFFFD6565), const Color(0x33FD6565)),
      'processing' => ('Обработка', const Color(0xFF8AB4F8), const Color(0x338AB4F8)),
      'archived' => ('Архив', AppColors.fitGrey, const Color(0xFF2A2A2A)),
      _ => (_videoStatus(status), AppColors.fitGrey, const Color(0xFF2A2A2A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class VideoCreatePage extends StatefulWidget {
  const VideoCreatePage({super.key, this.initialVideo});

  final Map<String, dynamic>? initialVideo;

  @override
  State<VideoCreatePage> createState() => _VideoCreatePageState();
}

enum _VideoSource { youtube, file }

class _VideoCreatePageState extends State<VideoCreatePage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _videoUrl = TextEditingController();
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _topics = const [];
  int? _categoryId;
  int? _topicId;
  String _level = 'beginner';
  _VideoSource _source = _VideoSource.youtube;
  String? _videoPath;
  String? _videoName;
  int? _videoBytes;
  String? _thumbPath;
  String? _thumbName;
  bool _saving = false;
  bool _loading = true;
  String? _titleError;
  String? _sourceError;
  String? _metaError;
  int? _editId;
  String? _existingCoverUrl;

  bool get _isEdit => _editId != null;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onDirty);
    _description.addListener(_onDirty);
    _videoUrl.addListener(_onYoutubeChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _title.removeListener(_onDirty);
    _description.removeListener(_onDirty);
    _videoUrl.removeListener(_onYoutubeChanged);
    _title.dispose();
    _description.dispose();
    _videoUrl.dispose();
    super.dispose();
  }

  void _onDirty() {
    if (_titleError != null && _title.text.trim().isNotEmpty) {
      setState(() => _titleError = null);
    } else {
      setState(() {});
    }
  }

  void _onYoutubeChanged() {
    setState(() {
      if (_sourceError != null) _sourceError = null;
    });
  }

  bool get _dirty {
    return _title.text.trim().isNotEmpty ||
        _description.text.trim().isNotEmpty ||
        _videoUrl.text.trim().isNotEmpty ||
        _videoPath != null ||
        _thumbPath != null ||
        _categoryId != null ||
        _topicId != null;
  }

  String? get _categoryLabel {
    if (_categoryId == null) return null;
    for (final item in _categories) {
      if (int.tryParse('${item['id']}') == _categoryId) {
        return item['name']?.toString() ?? item['title']?.toString();
      }
    }
    return null;
  }

  String? get _topicLabel {
    if (_topicId == null) return null;
    for (final item in _topics) {
      if (int.tryParse('${item['id']}') == _topicId) {
        return item['name']?.toString() ?? item['title']?.toString();
      }
    }
    return null;
  }

  String? get _youtubeId => _source == _VideoSource.youtube ? youtubeVideoId(_videoUrl.text) : null;

  String? get _autoCoverUrl {
    final id = _youtubeId;
    return id == null ? null : 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }

  String? get _effectiveCoverUrl {
    if (_thumbPath != null) return null; // local file handled separately
    return _autoCoverUrl ?? _existingCoverUrl;
  }

  Future<void> _bootstrap() async {
    try {
      final categories = await FitApi.videoCategories();
      if (!mounted) return;
      final initial = widget.initialVideo;
      if (initial != null) {
        _editId = int.tryParse('${initial['id']}');
        _title.text = initial['title']?.toString() ?? '';
        _description.text = initial['description']?.toString() ?? '';
        final url = initial['video_url']?.toString() ?? '';
        if (isYoutubeUrl(url)) {
          _source = _VideoSource.youtube;
          _videoUrl.text = url;
        } else if (url.isNotEmpty) {
          _source = _VideoSource.file;
          _videoName = 'Текущий файл видео';
        }
        _level = initial['level']?.toString().isNotEmpty == true ? initial['level'].toString() : 'beginner';
        _categoryId = int.tryParse('${initial['category_id']}');
        _topicId = int.tryParse('${initial['topic_id']}');
        _existingCoverUrl = initial['thumbnail_url']?.toString();
      }
      setState(() {
        _categories = categories;
        _loading = false;
      });
      if (_categoryId != null) {
        try {
          final topics = await FitApi.categoryTopics(_categoryId!);
          if (mounted) setState(() => _topics = topics);
        } catch (_) {}
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _pickCategory() async {
    if (_categories.isEmpty) {
      Toast.info('Категории пока недоступны');
      return;
    }
    final id = await _showOptionSheet<int>(
      title: 'Категория',
      options: [
        for (final item in _categories)
          (
            value: int.tryParse('${item['id']}') ?? 0,
            label: item['name']?.toString() ?? item['title']?.toString() ?? 'Категория',
          ),
      ].where((e) => e.value > 0).toList(),
      selected: _categoryId,
    );
    if (id == null || !mounted) return;
    setState(() {
      _categoryId = id;
      _topicId = null;
      _topics = const [];
      _metaError = null;
    });
    try {
      final topics = await FitApi.categoryTopics(id);
      if (mounted) setState(() => _topics = topics);
    } catch (error) {
      Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _pickTopic() async {
    if (_categoryId == null) {
      Toast.info('Сначала выберите категорию');
      return;
    }
    if (_topics.isEmpty) {
      Toast.info('В этой категории пока нет тем');
      return;
    }
    final id = await _showOptionSheet<int>(
      title: 'Тема',
      options: [
        for (final item in _topics)
          (
            value: int.tryParse('${item['id']}') ?? 0,
            label: item['name']?.toString() ?? item['title']?.toString() ?? 'Тема',
          ),
      ].where((e) => e.value > 0).toList(),
      selected: _topicId,
    );
    if (id == null || !mounted) return;
    setState(() {
      _topicId = id;
      _metaError = null;
    });
  }

  Future<T?> _showOptionSheet<T>({
    required String title,
    required List<({T value, String label})> options,
    T? selected,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFF3A3A3A), borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF2A2A2A)),
                  itemBuilder: (_, i) {
                    final opt = options[i];
                    final on = opt.value == selected;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(opt.label, style: TextStyle(color: on ? AppColors.accent : Colors.white, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                      trailing: on ? const Icon(Icons.radio_button_checked, color: AppColors.accent, size: 20) : const Icon(Icons.radio_button_off, color: Color(0xFF6B6B6B), size: 20),
                      onTap: () => Navigator.pop(ctx, opt.value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickVideoFile() async {
    final files = await FilePicker.pickFiles(type: FileType.video);
    if (files.isEmpty) return;
    final file = files.first;
    final path = file.path;
    if (path == null) return;
    setState(() {
      _videoPath = path;
      _videoName = file.name;
      _videoBytes = file.lengthSync();
      _videoUrl.clear();
      _sourceError = null;
    });
  }

  Future<void> _pickCover() async {
    try {
      final prepared = await pickPreparedImage();
      if (prepared == null) return;
      setState(() {
        _thumbPath = prepared.path;
        _thumbName = prepared.filename;
      });
    } catch (e) {
      Toast.error(e is FormatException ? e.message : FitApi.messageOf(e));
    }
  }

  void _clearCover() => setState(() {
        _thumbPath = null;
        _thumbName = null;
      });

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  bool _validate() {
    String? titleError;
    String? sourceError;
    String? metaError;
    if (_title.text.trim().isEmpty) titleError = 'Введите название';
    if (_source == _VideoSource.youtube) {
      final url = _videoUrl.text.trim();
      if (url.isEmpty && !_isEdit) {
        sourceError = 'Вставьте ссылку YouTube';
      } else if (url.isNotEmpty && !isYoutubeUrl(url)) {
        sourceError = 'Нужна ссылка youtube.com или youtu.be';
      }
    } else if (_videoPath == null && !_isEdit) {
      sourceError = 'Выберите видеофайл';
    }
    if (_categoryId == null || _topicId == null) {
      metaError = 'Выберите категорию и тему';
    }
    setState(() {
      _titleError = titleError;
      _sourceError = sourceError;
      _metaError = metaError;
    });
    return titleError == null && sourceError == null && metaError == null;
  }

  Future<void> _save() async {
    if (_saving || !_validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await FitApi.updateTrainerVideo(
          _editId!,
          title: _title.text.trim(),
          categoryId: _categoryId,
          topicId: _topicId,
          description: _description.text.trim(),
          level: _level,
          videoUrl: _source == _VideoSource.youtube && _videoUrl.text.trim().isNotEmpty ? _videoUrl.text.trim() : null,
          videoPath: _source == _VideoSource.file ? _videoPath : null,
          thumbnailPath: _thumbPath,
        );
      } else {
        // Personal library only — do not auto-submit individual videos.
        await FitApi.createTrainerVideo(
          title: _title.text.trim(),
          categoryId: _categoryId!,
          topicId: _topicId!,
          description: _description.text.trim(),
          level: _level,
          videoUrl: _source == _VideoSource.youtube ? _videoUrl.text.trim() : null,
          submit: false,
          videoPath: _source == _VideoSource.file ? _videoPath : null,
          thumbnailPath: _thumbPath,
        );
      }
      if (!mounted) return;
      Toast.success(_isEdit ? 'Изменения сохранены' : 'Видео сохранено в библиотеку');
      context.pop(true);
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleBack() async {
    final leave = await _confirmLeave();
    if (!mounted || !leave) return;
    context.pop();
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _saving) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.fitCard,
        title: const Text('Выйти без сохранения?', style: TextStyle(color: Colors.white)),
        content: const Text('Изменения будут потеряны.', style: TextStyle(color: AppColors.fitGrey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти', style: TextStyle(color: Color(0xFFFD6565))),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (!mounted || !leave) return;
        context.pop();
      },
      child: FitScaffold(
        padding: EdgeInsets.zero,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: HubBackTitle(
                      title: _isEdit ? 'Редактировать видео' : 'Новое видео',
                      onBack: _handleBack,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        _sectionLabel('Основное'),
                        const SizedBox(height: 8),
                        _CompactField(
                          label: 'Название',
                          controller: _title,
                          errorText: _titleError,
                        ),
                        const SizedBox(height: 8),
                        _CompactField(
                          label: 'Описание',
                          controller: _description,
                          maxLines: 3,
                          minLines: 2,
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel('Источник'),
                        const SizedBox(height: 8),
                        _SourceToggle(
                          value: _source,
                          onChanged: (value) => setState(() {
                            _source = value;
                            _sourceError = null;
                            if (value == _VideoSource.youtube) {
                              _videoPath = null;
                              _videoName = null;
                              _videoBytes = null;
                            } else {
                              _videoUrl.clear();
                            }
                          }),
                        ),
                        const SizedBox(height: 10),
                        if (_source == _VideoSource.youtube) ...[
                          _CompactField(
                            label: 'Ссылка YouTube',
                            controller: _videoUrl,
                            keyboardType: TextInputType.url,
                            errorText: _sourceError,
                          ),
                          if (_videoUrl.text.trim().isNotEmpty && _youtubeId == null && _sourceError == null)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'Вставьте корректную ссылку youtube.com / youtu.be',
                                style: TextStyle(color: Color(0xFFFD6565), fontSize: 12),
                              ),
                            ),
                          if (_youtubeId != null) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 220),
                                child: _YoutubeThumbPreview(key: ValueKey(_youtubeId), videoId: _youtubeId!),
                              ),
                            ),
                          ],
                        ] else ...[
                          _FilePickCard(
                            title: _videoPath == null ? 'Выбрать видео' : (_videoName ?? 'Видео выбрано'),
                            subtitle: _videoPath == null
                                ? 'MP4, MOV, WEBM'
                                : [
                                    if (_formatBytes(_videoBytes).isNotEmpty) _formatBytes(_videoBytes),
                                    'Готово к загрузке',
                                  ].where((e) => e.isNotEmpty).join(' · '),
                            accent: true,
                            onTap: _pickVideoFile,
                            onClear: _videoPath == null
                                ? null
                                : () => setState(() {
                                      _videoPath = null;
                                      _videoName = null;
                                      _videoBytes = null;
                                    }),
                          ),
                          if (_sourceError != null) ...[
                            const SizedBox(height: 6),
                            Text(_sourceError!, style: const TextStyle(color: Color(0xFFFD6565), fontSize: 12)),
                          ],
                        ],
                        const SizedBox(height: 14),
                        _sectionLabel('Обложка'),
                        const SizedBox(height: 8),
                        _CoverBlock(
                          localPath: _thumbPath,
                          networkUrl: _thumbPath == null ? _effectiveCoverUrl : null,
                          customFileName: _thumbName,
                          isCustom: _thumbPath != null,
                          isYoutubeSource: _source == _VideoSource.youtube,
                          hasAutoYoutube: _source == _VideoSource.youtube && _autoCoverUrl != null,
                          onUpload: _pickCover,
                          onUseAuto: _thumbPath != null && _source == _VideoSource.youtube && _autoCoverUrl != null
                              ? _clearCover
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel('Категории и уровень'),
                        const SizedBox(height: 8),
                        _SelectRow(
                          label: 'Категория',
                          value: _categoryLabel ?? 'Выбрать',
                          placeholder: _categoryLabel == null,
                          onTap: _pickCategory,
                        ),
                        const SizedBox(height: 8),
                        _SelectRow(
                          label: 'Тема',
                          value: _topicLabel ?? (_categoryId == null ? 'Сначала категория' : 'Выбрать'),
                          placeholder: _topicLabel == null,
                          onTap: _pickTopic,
                        ),
                        if (_metaError != null) ...[
                          const SizedBox(height: 6),
                          Text(_metaError!, style: const TextStyle(color: Color(0xFFFD6565), fontSize: 12)),
                        ],
                        const SizedBox(height: 12),
                        const Text('Уровень', style: TextStyle(color: AppColors.fitGrey, fontSize: 13)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final level in const ['beginner', 'intermediate', 'advanced'])
                              ChoiceChip(
                                label: Text(_videoLevel(level)),
                                selected: _level == level,
                                showCheckmark: false,
                                onSelected: (_) => setState(() => _level = level),
                                selectedColor: AppColors.accent,
                                labelStyle: TextStyle(
                                  color: _level == level ? Colors.black : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                backgroundColor: const Color(0xFF232323),
                                side: BorderSide(color: _level == level ? AppColors.accent : const Color(0xFF3A3A3A)),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Видео сохранится в личную библиотеку. В общий каталог оно не публикуется.',
                          style: TextStyle(color: AppColors.fitGrey, fontSize: 12, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  ColoredBox(
                    color: const Color(0xFF0D0D0D),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + (bottomInset > 0 ? 8 : MediaQuery.paddingOf(context).bottom)),
                      child: FitAccentButton(
                        title: _isEdit ? 'Сохранить изменения' : 'Сохранить видео',
                        loading: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
      );
}

class _SourceToggle extends StatelessWidget {
  const _SourceToggle({required this.value, required this.onChanged});

  final _VideoSource value;
  final ValueChanged<_VideoSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF323232)),
      ),
      child: Row(
        children: [
          Expanded(child: _tab('YouTube', _VideoSource.youtube)),
          Expanded(child: _tab('Видеофайл', _VideoSource.file)),
        ],
      ),
    );
  }

  Widget _tab(String label, _VideoSource source) {
    final on = value == source;
    return GestureDetector(
      onTap: () => onChanged(source),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: on ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: on ? Colors.black : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.minLines = 1,
    this.keyboardType,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final int minLines;
  final TextInputType? keyboardType;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: minLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.25),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 13),
            floatingLabelStyle: TextStyle(color: hasError ? const Color(0xFFFD6565) : AppColors.fitGrey, fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF232323),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: hasError ? const Color(0xFFFD6565) : const Color(0xFF323232)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: hasError ? const Color(0xFFFD6565) : AppColors.accent, width: 1.3),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 4),
          Text(errorText!, style: const TextStyle(color: Color(0xFFFD6565), fontSize: 12)),
        ],
      ],
    );
  }
}

class _YoutubeThumbPreview extends StatelessWidget {
  const _YoutubeThumbPreview({super.key, required this.videoId});

  final String videoId;

  @override
  Widget build(BuildContext context) {
    final url = 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              url,
              key: ValueKey(url),
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const ColoredBox(
                  color: Color(0xFF222222),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                    ),
                  ),
                );
              },
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Color(0xFF222222),
                child: Center(
                  child: Text('Превью недоступно', style: TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text('Превью выбранного видео', style: TextStyle(color: AppColors.fitGrey, fontSize: 11)),
      ],
    );
  }
}

class _CoverBlock extends StatelessWidget {
  const _CoverBlock({
    required this.isCustom,
    required this.isYoutubeSource,
    required this.hasAutoYoutube,
    required this.onUpload,
    this.localPath,
    this.networkUrl,
    this.customFileName,
    this.onUseAuto,
  });

  final String? localPath;
  final String? networkUrl;
  final String? customFileName;
  final bool isCustom;
  final bool isYoutubeSource;
  final bool hasAutoYoutube;
  final VoidCallback onUpload;
  final VoidCallback? onUseAuto;

  String get _title {
    if (isCustom) return 'Своя обложка';
    if (isYoutubeSource && hasAutoYoutube) return 'Обложка YouTube';
    return 'Обложка не выбрана';
  }

  String get _subtitle {
    if (isCustom) {
      final name = customFileName?.trim();
      if (name != null && name.isNotEmpty) return name;
      return 'Будет загружена при сохранении';
    }
    if (isYoutubeSource && hasAutoYoutube) return 'Автоматически из видео';
    if (isYoutubeSource) return 'Появится после корректной ссылки';
    return 'Кадр из файла или своя картинка';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 88,
                  height: 50,
                  child: localPath != null
                      ? Image.file(
                          File(localPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : networkUrl != null
                          ? Image.network(
                              networkUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _placeholder(),
                            )
                          : _placeholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(_subtitle, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12, height: 1.25)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CoverActionChip(
                icon: Icons.image_outlined,
                label: isCustom ? 'Заменить обложку' : 'Загрузить свою обложку',
                onTap: onUpload,
              ),
              if (onUseAuto != null)
                _CoverActionChip(
                  icon: Icons.refresh_rounded,
                  label: 'Вернуть YouTube',
                  onTap: onUseAuto!,
                  muted: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => const ColoredBox(
        color: Color(0xFF2A2A2A),
        child: Center(child: Icon(Icons.image_outlined, color: AppColors.fitGrey, size: 18)),
      );
}

class _CoverActionChip extends StatelessWidget {
  const _CoverActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: muted ? const Color(0xFF232323) : AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: muted ? const Color(0xFF3A3A3A) : AppColors.accent.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: muted ? AppColors.fitGrey : AppColors.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: muted ? Colors.white70 : AppColors.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF323232)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: placeholder ? AppColors.fitGrey : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

class _FilePickCard extends StatelessWidget {
  const _FilePickCard({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.onClear,
  });

  final String title;
  final String subtitle;
  final bool accent;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent ? AppColors.accent.withValues(alpha: 0.12) : const Color(0xFF232323),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent ? AppColors.accent.withValues(alpha: 0.45) : const Color(0xFF323232)),
        ),
        child: Row(
          children: [
            Icon(accent ? Icons.videocam_outlined : Icons.image_outlined, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, color: AppColors.fitGrey, size: 18),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Client: assigned ─────────────────────────────────────────────────────────

class AssignedVideosPage extends StatefulWidget {
  const AssignedVideosPage({super.key});

  @override
  State<AssignedVideosPage> createState() => _AssignedVideosPageState();
}

class _AssignedVideosPageState extends State<AssignedVideosPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _videos = const [];
  List<Map<String, dynamic>> _programs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final videos = await FitApi.myAssignedVideos();
      List<Map<String, dynamic>> programs = const [];
      try {
        programs = await FitApi.myAssignedPrograms();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _programs = programs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const HubBackTitle(title: 'Назначено тренером'),
          TabBar(
            controller: _tabs,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.fitGrey,
            indicatorColor: AppColors.accent,
            tabs: const [
              Tab(text: 'Видео'),
              Tab(text: 'Курсы'),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      RefreshIndicator(
                        color: AppColors.accent,
                        onRefresh: _load,
                        child: _videos.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 80),
                                  Center(child: Text('Нет назначенных видео', style: TextStyle(color: AppColors.fitGrey))),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.only(top: 12, bottom: 40),
                                itemCount: _videos.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = _videos[index];
                                  final assignmentId = int.tryParse('${item['id']}') ?? 0;
                                  final video = item['video'] is Map ? Map<String, dynamic>.from(item['video'] as Map) : item;
                                  final videoId = int.tryParse('${video['id']}') ?? 0;
                                  return _VideoTile(
                                    video: video,
                                    onTap: () {
                                      if (videoId == 0 && assignmentId == 0) return;
                                      context.push(RouteNames.videoPlayer, extra: {
                                        'videoId': videoId,
                                        'assignmentId': assignmentId,
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                      RefreshIndicator(
                        color: AppColors.accent,
                        onRefresh: _load,
                        child: _programs.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 80),
                                  Center(child: Text('Нет назначенных курсов', style: TextStyle(color: AppColors.fitGrey))),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.only(top: 12, bottom: 40),
                                itemCount: _programs.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (_, i) {
                                  final p = _programs[i];
                                  return _AssignedProgramTile(
                                    program: p,
                                    onTap: () {
                                      final programId = int.tryParse('${p['id']}') ?? 0;
                                      if (programId == 0) return;
                                      context.push(RouteNames.programDetail, extra: programId);
                                    },
                                  );
                                },
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

class _AssignedProgramTile extends StatelessWidget {
  const _AssignedProgramTile({required this.program, required this.onTap});

  final Map<String, dynamic> program;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = program['title']?.toString().trim().isNotEmpty == true
        ? program['title'].toString()
        : 'Курс';
    final note = program['note']?.toString().trim() ?? '';
    final cover = program['cover_url']?.toString() ?? '';
    final weeks = int.tryParse('${program['duration_weeks']}') ?? 0;
    final level = _videoLevel(program['level']?.toString());
    final assigned = DateHelper.formatRuAny(program['assigned_at'], withTime: false);
    final isPro = program['is_pro'] == true;
    final meta = [
      if (level != '—') level,
      if (weeks > 0) '$weeks нед.',
      if (isPro) 'PRO',
    ].join(' · ');

    return GestureDetector(
      onTap: onTap,
      child: HubCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: cover.isNotEmpty
                    ? Image.network(
                        cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFF2A2A2A),
                          child: const Icon(Icons.fitness_center, color: AppColors.fitGrey),
                        ),
                      )
                    : Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(Icons.fitness_center, color: AppColors.fitGrey),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(meta, style: const TextStyle(color: AppColors.fitGrey, fontSize: 12)),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Назначено: $assigned',
                    style: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      note,
                      style: const TextStyle(color: Color(0xFFC7F137), fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

// ─── Coach: assign to client ──────────────────────────────────────────────────

class AssignVideosPage extends StatefulWidget {
  const AssignVideosPage({super.key, required this.linkId, required this.clientName});

  final int linkId;
  final String clientName;

  @override
  State<AssignVideosPage> createState() => _AssignVideosPageState();
}

class _AssignVideosPageState extends State<AssignVideosPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _mine = const [];
  List<Map<String, dynamic>> _library = const [];
  List<Map<String, dynamic>> _assigned = const [];
  final _selected = <int>{};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final mine = await FitApi.myTrainerVideos(status: 'published');
      final library = await FitApi.videos();
      final assigned = await FitApi.clientAssignedVideos(widget.linkId);
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _library = library.where((item) => item['source_type']?.toString() == 'admin' || item['source_type'] == null).toList();
        _assigned = assigned;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      Toast.error(FitApi.messageOf(error));
    }
  }

  Future<void> _assign() async {
    if (_selected.isEmpty) {
      Toast.info('Выберите хотя бы одно видео');
      return;
    }
    setState(() => _saving = true);
    try {
      await FitApi.assignVideosToClient(widget.linkId, _selected.toList());
      if (!mounted) return;
      Toast.success('Видео назначены');
      _selected.clear();
      await _load();
    } catch (error) {
      if (mounted) Toast.error(FitApi.messageOf(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unassign(int assignmentId) async {
    try {
      await FitApi.unassignClientVideo(widget.linkId, assignmentId);
      Toast.info('Назначение снято');
      _load();
    } catch (error) {
      Toast.error(FitApi.messageOf(error));
    }
  }

  Widget _pickerList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(child: Text('Список пуст', style: TextStyle(color: AppColors.fitGrey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final id = int.tryParse('${item['id']}') ?? 0;
        final selected = _selected.contains(id);
        return _VideoTile(
          video: item,
          onTap: () {
            if (id == 0) return;
            setState(() {
              if (selected) {
                _selected.remove(id);
              } else {
                _selected.add(id);
              }
            });
          },
          trailing: Checkbox(
            value: selected,
            activeColor: AppColors.accent,
            checkColor: Colors.black,
            onChanged: (_) {
              if (id == 0) return;
              setState(() {
                if (selected) {
                  _selected.remove(id);
                } else {
                  _selected.add(id);
                }
              });
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          HubBackTitle(title: 'Видеоуроки · ${widget.clientName}'),
          if (_assigned.isNotEmpty) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Уже назначено', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _assigned.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = _assigned[index];
                  final assignmentId = int.tryParse('${item['id']}') ?? 0;
                  final video = item['video'] is Map ? Map<String, dynamic>.from(item['video'] as Map) : item;
                  return SizedBox(
                    width: 220,
                    child: _VideoTile(
                      video: video,
                      onTap: () {},
                      trailing: IconButton(
                        onPressed: assignmentId == 0 ? null : () => _unassign(assignmentId),
                        icon: const Icon(Icons.close, color: Color(0xFFFF6B6B), size: 18),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
          TabBar(
            controller: _tabs,
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: Colors.white70,
            tabs: const [Tab(text: 'Мои'), Tab(text: 'Общая библиотека')],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : TabBarView(
                    controller: _tabs,
                    children: [_pickerList(_mine), _pickerList(_library)],
                  ),
          ),
          FitAccentButton(
            title: _selected.isEmpty ? 'Назначить' : 'Назначить (${_selected.length})',
            onPressed: _saving ? null : _assign,
            loading: _saving,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
