import 'package:dio/dio.dart';
import 'package:trainhub/core/config/api_config.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/exceptions/app_exceptions.dart';
import 'package:trainhub/core/network/api_service.dart';
import 'package:trainhub/core/utils/date_helper.dart';
import 'package:trainhub/core/utils/image_upload.dart';
import 'package:trainhub/features/fitpro/fit_cache.dart';
import 'package:trainhub/features/fitpro/fit_labels.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/services/local_storage/storage_service.dart';

/// Resolves `/media/...` and absolute URLs for Image.network.
class FitMedia {
  FitMedia._();

  static String? url(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    final api = Uri.parse(ApiConfig.baseUrl);
    final origin = '${api.scheme}://${api.host}${api.hasPort ? ':${api.port}' : ''}';
    if (value.startsWith('/')) return '$origin$value';
    return '$origin/$value';
  }

  /// First exercise photo from catalog / day-exercise payload.
  static String? exercisePhoto(Map<String, dynamic> item) {
    final single = url(item['photo_url']?.toString());
    if (single != null) return single;
    final urls = item['photo_urls'];
    if (urls is List && urls.isNotEmpty) return url(urls.first.toString());
    return null;
  }
}

class FitCalendarEvent {
  const FitCalendarEvent({
    required this.id,
    required this.name,
    required this.place,
    required this.online,
    required this.status,
    required this.tags,
    required this.time,
    this.startsAt,
    this.endsAt,
    this.durationMin = 0,
    this.rawStatus = '',
  });

  final int id;
  final String name;
  final String place;
  final bool online;
  final String status;
  final List<String> tags;
  final String time;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int durationMin;
  final String rawStatus;

  factory FitCalendarEvent.fromJson(Map<String, dynamic> json) {
    final start = DateTime.tryParse(json['starts_at']?.toString() ?? '')?.toLocal();
    final end = DateTime.tryParse(json['ends_at']?.toString() ?? '')?.toLocal();
    final format = json['format']?.toString() ?? '';
    final kinds = _strings(json['kinds']);
    final muscles = _strings(json['focus_muscles']);
    final tags = [...kinds.map(_kindLabel), ...muscles.map(_muscleLabel)].where((item) => item.isNotEmpty).toList();
    final duration = _int(json['duration_min']);
    final computed = duration > 0
        ? duration
        : (start != null && end != null ? end.difference(start).inMinutes : 0);
    return FitCalendarEvent(
      id: _int(json['id']),
      name: _personName(json),
      place: _formatLabel(format),
      online: format == 'online',
      status: _statusLabel(json['status']?.toString() ?? ''),
      tags: tags.isEmpty ? const ['Тренировка'] : tags,
      time: start == null ? '' : '${_hhmm(start)} - ${end == null ? '' : _hhmm(end)}'.trim(),
      startsAt: start,
      endsAt: end,
      durationMin: computed,
      rawStatus: json['status']?.toString() ?? '',
    );
  }
}

class FitAttentionItem {
  const FitAttentionItem({
    required this.id,
    required this.name,
    required this.days,
    required this.place,
    this.phone = '',
    this.whatsapp = '',
    this.telegram = '',
    this.linkId = 0,
    this.weightKg,
    this.targetWeightKg,
    this.clientSince,
    this.subscriptionEndsAt,
  });

  final int id;
  final String name;
  final int days;
  final String place;
  final String phone;
  final String whatsapp;
  final String telegram;
  final int linkId;
  final String? weightKg;
  final String? targetWeightKg;
  final String? clientSince;
  final String? subscriptionEndsAt;

  factory FitAttentionItem.fromJson(Map<String, dynamic> json) {
    final days = _int(json['days_inactive']);
    return FitAttentionItem(
      id: _int(json['id']),
      name: _personName(json),
      days: days,
      place: _formatLabel(json['training_format']?.toString() ?? ''),
      phone: json['phone']?.toString() ?? '',
      whatsapp: json['whatsapp']?.toString() ?? '',
      telegram: json['telegram']?.toString() ?? '',
      linkId: _int(json['link_id']),
      weightKg: json['weight_kg']?.toString(),
      targetWeightKg: json['target_weight_kg']?.toString(),
      clientSince: json['client_since']?.toString(),
      subscriptionEndsAt: json['subscription_ends_at']?.toString(),
    );
  }
}

class FitSearchUser {
  const FitSearchUser({
    required this.userId,
    required this.name,
    required this.publicId,
    required this.alreadyAdded,
    required this.goals,
    required this.place,
    required this.online,
  });

  final int userId;
  final String name;
  final String publicId;
  final bool alreadyAdded;
  final int goals;
  final String place;
  final bool online;

  factory FitSearchUser.fromJson(Map<String, dynamic> json) {
    final format = json['training_format']?.toString() ?? '';
    return FitSearchUser(
      userId: _int(json['user_id'] ?? json['id']),
      name: _personName(json),
      publicId: json['public_id']?.toString() ?? '',
      alreadyAdded: json['already_added'] == true,
      goals: _int(json['goals_count']),
      place: _formatLabel(format),
      online: format == 'online',
    );
  }
}

class FitNote {
  const FitNote({required this.id, required this.title, required this.body, required this.createdAt});

  final int id;
  final String title;
  final String body;
  final String createdAt;

  factory FitNote.fromJson(Map<String, dynamic> json) {
    return FitNote(
      id: _int(json['id']),
      title: json['title']?.toString() ?? json['text']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

class FitNotice {
  const FitNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.type = '',
    this.payload = const {},
  });

  final int id;
  final String title;
  final String body;
  final bool isRead;
  final DateTime? createdAt;
  final String type;
  final Map<String, dynamic> payload;

  factory FitNotice.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload_json'] ?? json['payload'];
    return FitNotice(
      id: _int(json['id']),
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      isRead: json['is_read'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
      type: json['type']?.toString() ?? '',
      payload: rawPayload is Map ? Map<String, dynamic>.from(rawPayload) : const {},
    );
  }
}

class FitApi {
  FitApi._();

  static ApiService get _api => getIt<ApiService>();
  static StorageService get _storage => getIt<StorageService>();

  static String messageOf(Object error) {
    if (error is NetworkException) return 'Нет соединения с сервером';
    if (error is TimeoutException) return 'Сервер не отвечает. Попробуйте ещё раз';
    if (error is FormatException && error.message.isNotEmpty) return error.message;
    if (error is AppException && error.message.isNotEmpty) return error.message;
    return 'Не удалось выполнить запрос';
  }

  static void _invalidateMeasurementCaches() {
    FitCache.I.invalidateAll(const ['home', 'measurements', 'progress', 'chart']);
  }

  static void _invalidateTrainerCaches() {
    FitCache.I.invalidateAll(const [
      'trainer.dashboard',
      'trainer.attention',
      'trainer.calendar',
      'trainer.clients',
    ]);
  }

  static Future<FitUser> login({required String login, required String password}) async {
    final response = await _api.post<Map<String, dynamic>>('/auth/login', data: {
      'login': login,
      'password': password,
    });
    return _saveSession(response.data);
  }

  static Future<FitUser> register({
    required String firstName,
    required String lastName,
    String? email,
    String? phone,
    required String password,
    required FitRole role,
    String? gender,
    String? birthDate,
  }) async {
    final response = await _api.post<Map<String, dynamic>>('/auth/register', data: {
      'first_name': firstName,
      'last_name': lastName,
      if (email != null && email.isNotEmpty) 'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'password': password,
      'role': role.name,
      if (gender != null) 'gender': gender,
      if (birthDate != null) 'birth_date': birthDate,
    });
    return _saveSession(response.data);
  }

  static Future<Map<String, dynamic>> telegramSendCode(String identifier) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/auth/telegram/send-code',
      data: {'identifier': identifier},
    );
    return _asMap(_unwrap(response.data));
  }

  static Future<FitUser> telegramVerify({
    required String identifier,
    required String code,
    required FitRole role,
  }) async {
    final response = await _api.post<Map<String, dynamic>>('/auth/telegram/verify', data: {
      'identifier': identifier,
      'code': code,
      'role': role.name,
    });
    return _saveSession(response.data);
  }

  static Future<void> passwordResetRequest(String login) async {
    await _api.post<dynamic>('/auth/password-reset/request', data: {'login': login});
  }

  static Future<void> passwordResetConfirm({required String token, required String newPassword}) async {
    await _api.post<dynamic>('/auth/password-reset/confirm', data: {
      'token': token,
      'new_password': newPassword,
    });
  }

  /// Social sign-in fails with [isRoleRequired] for a brand-new account sent without a role.
  static bool isRoleRequired(Object error) => error is ApiException && error.code == 'ROLE_REQUIRED';

  static Future<FitUser> google({required String idToken, FitRole? role}) async {
    final response = await _api.post<Map<String, dynamic>>('/auth/google', data: {
      'id_token': idToken,
      if (role != null) 'role': role.name,
    });
    return _saveSession(response.data);
  }

  static Future<FitUser> apple({
    required String identityToken,
    FitRole? role,
    String? firstName,
    String? lastName,
  }) async {
    final response = await _api.post<Map<String, dynamic>>('/auth/apple', data: {
      'identity_token': identityToken,
      if (role != null) 'role': role.name,
      if (firstName != null && firstName.isNotEmpty) 'first_name': firstName,
      if (lastName != null && lastName.isNotEmpty) 'last_name': lastName,
    });
    return _saveSession(response.data);
  }

  static Future<FitUser> me() async {
    final response = await _api.get<Map<String, dynamic>>('/me');
    return fitUserFromJson(_asMap(_unwrap(response.data)));
  }

  static Future<FitUser> patchMe({
    String? firstName,
    String? lastName,
    String? phone,
    String? whatsapp,
    String? telegram,
    String? gender,
    String? birthDate,
    num? heightCm,
    num? weightGoalKg,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>('/me', data: {
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phone != null) 'phone': phone,
      if (whatsapp != null) 'whatsapp': whatsapp,
      if (telegram != null) 'telegram': telegram,
      if (gender != null) 'gender': gender,
      if (birthDate != null) 'birth_date': birthDate,
      if (heightCm != null) 'height_cm': heightCm,
      if (weightGoalKg != null) 'weight_goal_kg': weightGoalKg,
    });
    return fitUserFromJson(_asMap(_unwrap(response.data)));
  }

  static Future<void> registerDevice({
    required String token,
    required String platform,
    String? deviceName,
    String? appVersion,
  }) async {
    await _api.post<dynamic>('/me/devices', data: {
      'platform': platform,
      'token': token,
      if (deviceName != null) 'device_name': deviceName,
      if (appVersion != null) 'app_version': appVersion,
    });
  }

  static Future<void> logout() async {
    final refresh = _storage.getRefreshToken();
    try {
      if (refresh != null && refresh.isNotEmpty) {
        await _api.post<dynamic>('/auth/logout', data: {'refresh_token': refresh});
      }
    } finally {
      await _storage.clearAuth();
      await FitCache.I.clear();
    }
  }

  static Future<Map<String, dynamic>> trainerDashboard({bool force = false}) {
    return FitCache.I.get<Map<String, dynamic>>(
      key: 'trainer.dashboard',
      force: force,
      freshFor: const Duration(seconds: 45),
      keepFor: const Duration(hours: 24),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>('/trainer/dashboard');
        return _asMap(_unwrap(response.data));
      },
    );
  }

  static Future<int> unreadCount() async {
    final response = await _api.get<Map<String, dynamic>>('/notifications/unread-count');
    return _int(_asMap(_unwrap(response.data))['unread_count']);
  }

  static Future<List<FitCalendarEvent>> trainerCalendar({DateTime? from, DateTime? to, bool force = false}) async {
    final key = 'trainer.calendar.${from?.toIso8601String() ?? ''}.${to?.toIso8601String() ?? ''}';
    final raw = await FitCache.I.get<List<Map<String, dynamic>>>(
      key: key,
      force: force,
      freshFor: const Duration(seconds: 45),
      keepFor: const Duration(hours: 12),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>(
          '/trainer/calendar',
          queryParameters: {
            if (from != null) 'date_from': from.toUtc().toIso8601String(),
            if (to != null) 'date_to': to.toUtc().toIso8601String(),
          },
        );
        return _list(_unwrap(response.data));
      },
    );
    return raw.map(FitCalendarEvent.fromJson).toList();
  }

  static Future<List<FitCalendarEvent>> clientCalendar({DateTime? from, DateTime? to, bool force = false}) async {
    final key = 'client.calendar.${from?.toIso8601String() ?? ''}.${to?.toIso8601String() ?? ''}';
    final raw = await FitCache.I.get<List<Map<String, dynamic>>>(
      key: key,
      force: force,
      freshFor: const Duration(seconds: 45),
      keepFor: const Duration(hours: 12),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>(
          '/client/calendar',
          queryParameters: {
            if (from != null) 'date_from': from.toUtc().toIso8601String(),
            if (to != null) 'date_to': to.toUtc().toIso8601String(),
          },
        );
        return _list(_unwrap(response.data));
      },
    );
    return raw.map(FitCalendarEvent.fromJson).toList();
  }

  static Future<List<FitAttentionItem>> trainerAttention({bool force = false}) async {
    final raw = await FitCache.I.get<List<Map<String, dynamic>>>(
      key: 'trainer.attention',
      force: force,
      freshFor: const Duration(seconds: 45),
      keepFor: const Duration(hours: 12),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>('/trainer/attention');
        return _list(_unwrap(response.data));
      },
    );
    return raw.map(FitAttentionItem.fromJson).toList();
  }

  static Future<Map<String, dynamic>> trainerReport(String period) async {
    final response = await _api.get<Map<String, dynamic>>('/trainer/reports', queryParameters: {'period': period});
    return _asMap(_unwrap(response.data));
  }

  static Future<List<FitClient>> trainerClients({
    String? q,
    String? gender,
    String? format,
    String? status,
    String sort = 'newest',
    bool force = false,
  }) async {
    final key = 'trainer.clients|$q|$gender|$format|$status|$sort';
    final raw = await FitCache.I.get<List<Map<String, dynamic>>>(
      key: key,
      force: force,
      freshFor: const Duration(minutes: 1),
      keepFor: const Duration(hours: 24),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>(
          '/trainer/clients',
          queryParameters: {
            if (q != null && q.isNotEmpty) 'q': q,
            if (gender != null) 'gender': gender,
            if (format != null) 'format': format,
            if (status != null) 'status': status,
            'sort': sort,
            'page': 1,
            'page_size': 50,
          },
        );
        final data = _unwrap(response.data);
        final list = data is Map && data['items'] is List ? data['items'] as List : data;
        return _list(list);
      },
    );
    return raw.map(fitClientFromJson).toList();
  }

  static Future<List<FitSearchUser>> searchClients(String query) async {
    final response = await _api.post<Map<String, dynamic>>('/trainer/clients/search', data: {'query': query});
    return _list(_unwrap(response.data)).map(FitSearchUser.fromJson).toList();
  }

  static Future<void> addClient(int userId) async {
    await _api.post<dynamic>('/trainer/clients', data: {'user_id': userId});
    _invalidateTrainerCaches();
  }

  static Future<List<({String code, String title})>> fitnessGoals() async {
    final response = await _api.get<Map<String, dynamic>>('/dictionaries');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] as List : data;
    return _list(raw)
        .where((item) => item['category']?.toString() == 'fitness_goal')
        .map((item) => (code: item['code']?.toString() ?? '', title: item['title_ru']?.toString() ?? ''))
        .where((item) => item.code.isNotEmpty && item.title.isNotEmpty)
        .toList();
  }

  static Future<void> addClientManual({
    required String firstName,
    required String lastName,
    String? email,
    String? phone,
    String? birthDate,
    List<String> goals = const [],
    String? trainingFormat,
    Map<String, num> measurements = const {},
    List<String> contraindications = const [],
  }) async {
    await _api.post<dynamic>('/trainer/clients/manual', data: {
      'first_name': firstName,
      if (lastName.isNotEmpty) 'last_name': lastName,
      if (email != null && email.isNotEmpty) 'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (birthDate != null) 'birth_date': birthDate,
      if (goals.isNotEmpty) 'goals': goals,
      if (trainingFormat != null) 'training_format': trainingFormat,
      if (measurements.isNotEmpty) 'measurements': measurements,
      if (contraindications.isNotEmpty) 'contraindications': contraindications,
    });
  }

  static Future<Map<String, dynamic>> clientHome({bool force = false}) {
    return FitCache.I.get<Map<String, dynamic>>(
      key: 'home',
      force: force,
      freshFor: const Duration(seconds: 45),
      keepFor: const Duration(hours: 24),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>('/client/home');
        return _asMap(_unwrap(response.data));
      },
    );
  }

  static Future<List<FitNote>> clientNotes({String? q}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/client/notes',
      queryParameters: {if (q != null && q.isNotEmpty) 'q': q},
    );
    return _list(_unwrap(response.data)).map(FitNote.fromJson).toList();
  }

  static Future<void> createNote({required String title, String body = ''}) async {
    await _api.post<dynamic>('/client/notes', data: {'title': title, 'body': body});
  }

  static Future<void> updateNote({required int id, required String title, String body = ''}) async {
    await _api.patch<dynamic>('/client/notes/$id', data: {'title': title, 'body': body});
  }

  static Future<List<FitNote>> trainerNotes() async {
    final response = await _api.get<Map<String, dynamic>>('/client/trainer-notes');
    return _list(_unwrap(response.data)).map((item) {
      return FitNote(
        id: _int(item['id']),
        title: item['trainer_name']?.toString() ?? 'Тренер',
        body: item['text']?.toString() ?? item['body']?.toString() ?? '',
        createdAt: item['created_at']?.toString() ?? '',
      );
    }).toList();
  }

  static Future<List<FitNotice>> notifications(String tab) async {
    final response = await _api.get<Map<String, dynamic>>('/notifications', queryParameters: {'tab': tab});
    return _list(_unwrap(response.data)).map(FitNotice.fromJson).toList();
  }

  static Future<void> readAllNotifications() async {
    await _api.post<dynamic>('/notifications/read-all');
  }

  static Future<void> readNotification(int id) async {
    await _api.post<dynamic>('/notifications/$id/read');
  }

  static Future<List<({String title, String body})>> faq(String audience) async {
    final response = await _api.get<Map<String, dynamic>>('/faq', queryParameters: {'audience': audience});
    return _list(_unwrap(response.data)).map((item) {
      return (
        title: item['question']?.toString() ?? item['title']?.toString() ?? item['title_ru']?.toString() ?? '',
        body: item['answer']?.toString() ?? item['body']?.toString() ?? item['content']?.toString() ?? '',
      );
    }).where((item) => item.title.isNotEmpty).toList();
  }

  static Future<List<Map<String, dynamic>>> programs({
    String? source,
    bool? isPro,
    String? q,
    String? level,
    String? goal,
    String? equipment,
    int? durationWeeks,
    bool force = false,
  }) {
    final key = 'programs|$source|$isPro|$q|$level|$goal|$equipment|$durationWeeks';
    return FitCache.I.get<List<Map<String, dynamic>>>(
      key: key,
      force: force,
      freshFor: const Duration(minutes: 2),
      keepFor: const Duration(hours: 24),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>(
          '/programs',
          queryParameters: {
            if (source != null) 'source': source,
            if (isPro != null) 'is_pro': isPro,
            if (q != null && q.isNotEmpty) 'q': q,
            if (level != null && level.isNotEmpty) 'level': level,
            if (goal != null && goal.isNotEmpty) 'goal': goal,
            if (equipment != null && equipment.isNotEmpty) 'equipment': equipment,
            if (durationWeeks != null) 'duration_weeks': durationWeeks,
            'page': 1,
            'page_size': 50,
          },
        );
        final data = _unwrap(response.data);
        final raw = data is Map && data['items'] is List ? data['items'] : data;
        return _list(raw);
      },
    );
  }

  static Future<Map<String, dynamic>> createExercise({
    required String title,
    List<String> equipment = const [],
    String? muscle,
    String? category,
    String? description,
  }) async {
    final response = await _api.post<Map<String, dynamic>>('/exercises', data: {
      'title': title,
      if (equipment.isNotEmpty) 'equipment': equipment,
      if (muscle != null && muscle.isNotEmpty) 'focus_muscle': muscle,
      if (category != null && category.isNotEmpty) 'category': category,
      if (description != null && description.isNotEmpty) 'description': description,
    });
    return _asMap(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> clientMeasurements({bool force = false}) {
    return FitCache.I.get<List<Map<String, dynamic>>>(
      key: 'measurements',
      force: force,
      freshFor: const Duration(minutes: 2),
      keepFor: const Duration(hours: 24),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>('/client/measurements');
        return _list(_unwrap(response.data));
      },
    );
  }

  static Future<Map<String, dynamic>> clientProgress({bool force = false}) {
    return FitCache.I.get<Map<String, dynamic>>(
      key: 'progress',
      force: force,
      freshFor: const Duration(minutes: 2),
      keepFor: const Duration(hours: 24),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>('/client/progress');
        return _asMap(_unwrap(response.data));
      },
    );
  }

  static Future<List<({DateTime at, double value})>> measurementChart(
    String metric, {
    int? linkId,
    bool force = false,
  }) async {
    final key = linkId == null ? 'chart.$metric' : 'chart.$linkId.$metric';
    // Persist as List<Map> (JSON-safe), then map to records for UI.
    final points = await FitCache.I.get<List<Map<String, dynamic>>>(
      key: key,
      force: force,
      freshFor: const Duration(minutes: 5),
      keepFor: const Duration(hours: 24),
      fetch: () async {
        final path = linkId == null ? '/client/measurements/chart' : '/trainer/clients/$linkId/measurements/chart';
        final response = await _api.get<Map<String, dynamic>>(path, queryParameters: {'metric': metric});
        final data = _asMap(_unwrap(response.data));
        return _list(data['points']).map((item) {
          return <String, dynamic>{
            'recorded_at': item['recorded_at']?.toString() ?? item['date']?.toString() ?? '',
            'value': item['value'] ?? item['weight_kg'] ?? 0,
          };
        }).toList();
      },
    );
    return [
      for (final item in points)
        (
          at: DateTime.tryParse(item['recorded_at']?.toString() ?? '') ?? DateTime.now(),
          value: double.tryParse('${item['value']}'.replaceAll(',', '.')) ?? 0,
        ),
    ];
  }

  static Future<List<Map<String, dynamic>>> clientSessions({
    bool force = false,
    String? kind,
    String? format,
    bool? withTrainer,
    String sort = 'newest',
    int? durationMin,
    int? durationMax,
    String? q,
  }) {
    final cacheKey = 'sessions|$kind|$format|$withTrainer|$sort|$durationMin|$durationMax|$q';
    return FitCache.I.get<List<Map<String, dynamic>>>(
      key: cacheKey,
      force: force,
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>(
          '/client/sessions',
          queryParameters: {
            'page': 1,
            'page_size': 50,
            'sort': sort,
            if (kind != null && kind.isNotEmpty) 'kind': kind,
            if (format != null && format.isNotEmpty) 'format': format,
            if (withTrainer != null) 'with_trainer': withTrainer,
            if (durationMin != null) 'duration_min': durationMin,
            if (durationMax != null) 'duration_max': durationMax,
            if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
          },
        );
        final data = _unwrap(response.data);
        final raw = data is Map && data['items'] is List ? data['items'] : data;
        return _list(raw);
      },
    );
  }

  static Future<List<Map<String, dynamic>>> photoProgress({bool force = false}) {
    return FitCache.I.get<List<Map<String, dynamic>>>(
      key: 'photo-progress',
      force: force,
      freshFor: const Duration(minutes: 2),
      keepFor: const Duration(hours: 24),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>('/client/photo-progress');
        final data = _unwrap(response.data);
        final raw = data is Map && data['items'] is List ? data['items'] : data;
        return _list(raw);
      },
    );
  }

  static Future<List<Map<String, dynamic>>> plans(String audience) async {
    final response = await _api.get<Map<String, dynamic>>('/plans', queryParameters: {'audience': audience});
    return _list(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>?> subscription(String audience) async {
    final response = await _api.get<Map<String, dynamic>>('/me/subscription', queryParameters: {'audience': audience});
    final data = _unwrap(response.data);
    if (data == null) return null;
    final map = _asMap(data);
    return map.isEmpty ? null : map;
  }

  static Future<Map<String, dynamic>> checkout(int planId) async {
    final response = await _api.post<Map<String, dynamic>>('/me/subscription/checkout', data: {'plan_id': planId});
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> payment(int id) async {
    final response = await _api.get<Map<String, dynamic>>('/payments/$id');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> retryPayment(int id) async {
    final response = await _api.post<Map<String, dynamic>>('/payments/$id/retry');
    return _asMap(_unwrap(response.data));
  }

  static Future<void> cancelSubscription() async {
    await _api.post<dynamic>('/me/subscription/cancel');
  }

  static Future<void> resumeSubscription() async {
    await _api.post<dynamic>('/me/subscription/resume');
  }

  static Future<List<Map<String, dynamic>>> payments() async {
    final response = await _api.get<Map<String, dynamic>>('/payments');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<void> changePassword({required String oldPassword, required String newPassword}) async {
    await _api.post<dynamic>('/auth/change-password', data: {'old_password': oldPassword, 'new_password': newPassword});
  }

  static Future<Map<String, dynamic>> clientCard(int linkId) async {
    final response = await _api.get<Map<String, dynamic>>('/trainer/clients/$linkId');
    return _asMap(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> linkMeasurements(int linkId) async {
    final response = await _api.get<Map<String, dynamic>>('/trainer/clients/$linkId/measurements');
    return _list(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> linkSessions(int linkId) async {
    final response = await _api.get<Map<String, dynamic>>('/trainer/clients/$linkId/sessions');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<Map<String, dynamic>> trainerProfile() async {
    final response = await _api.get<Map<String, dynamic>>('/trainer/profile');
    return _asMap(_unwrap(response.data));
  }

  /// Active unfinished workout, or null. Stale (>1h) sessions are abandoned on server.
  static Future<Map<String, dynamic>?> activeSession({bool force = true}) async {
    final response = await _api.get<Map<String, dynamic>>('/me/active-session');
    final data = _unwrap(response.data);
    if (data == null) return null;
    if (data is Map && data.isEmpty) return null;
    return _asMap(data);
  }

  static Future<Map<String, dynamic>> startSession({
    List<int> clientIds = const [],
    int? programDayId,
    String source = 'new',
    List<String> kinds = const ['strength'],
  }) async {
    final token = _storage.getToken();
    if (token == null || token.isEmpty) {
      throw const UnauthorizedException('Требуется авторизация');
    }
    try {
      final response = await _api.post<Map<String, dynamic>>('/sessions', data: {
        'source': programDayId != null ? 'program' : source,
        'kinds': kinds,
        if (clientIds.isNotEmpty) 'client_ids': clientIds,
        if (programDayId != null) 'program_day_id': programDayId,
      });
      return _asMap(_unwrap(response.data));
    } on ApiException catch (e) {
      if (e.code == 'ACTIVE_SESSION_EXISTS') {
        final details = e.data is Map ? (e.data as Map)['error'] : null;
        final detailMap = details is Map ? details['details'] : null;
        final sid = int.tryParse('${detailMap is Map ? detailMap['session_id'] : ''}') ?? 0;
        throw ApiException(
          e.message,
          code: e.code,
          statusCode: e.statusCode,
          data: {
            'session_id': sid,
            if (e.data != null) 'raw': e.data,
          },
        );
      }
      rethrow;
    }
  }

  /// Session id from ACTIVE_SESSION_EXISTS error, if present.
  static int? activeSessionIdFromError(Object error) {
    if (error is! ApiException || error.code != 'ACTIVE_SESSION_EXISTS') return null;
    final data = error.data;
    if (data is Map) {
      final direct = int.tryParse('${data['session_id']}') ?? 0;
      if (direct > 0) return direct;
      final err = data['error'];
      if (err is Map) {
        final details = err['details'];
        if (details is Map) {
          final id = int.tryParse('${details['session_id']}') ?? 0;
          if (id > 0) return id;
        }
      }
    }
    return null;
  }

  /// Prefer resume of unfinished session; otherwise create. Never starts a second live workout.
  static Future<({int sessionId, bool resumed})> startOrResumeSession({
    List<int> clientIds = const [],
    int? programDayId,
    String source = 'new',
    List<String> kinds = const ['strength'],
  }) async {
    try {
      final active = await activeSession();
      final activeId = int.tryParse('${active?['id']}') ?? 0;
      if (activeId > 0) {
        return (sessionId: activeId, resumed: true);
      }
    } catch (_) {}
    try {
      final session = await startSession(
        clientIds: clientIds,
        programDayId: programDayId,
        source: source,
        kinds: kinds,
      );
      final id = int.tryParse('${session['id']}') ?? 0;
      return (sessionId: id, resumed: false);
    } on ApiException catch (e) {
      final existing = activeSessionIdFromError(e);
      if (existing != null && existing > 0) {
        return (sessionId: existing, resumed: true);
      }
      rethrow;
    }
  }

  static Future<void> resolveAttention(int id) async {
    await _api.post<dynamic>('/trainer/attention/$id/resolve');
    _invalidateTrainerCaches();
  }

  static Future<String> legal(String docType) async {
    final response = await _api.get<Map<String, dynamic>>('/legal/$docType');
    final data = _asMap(_unwrap(response.data));
    for (final key in ['body', 'content', 'text', 'html']) {
      final value = data[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  // ── Dictionaries ──────────────────────────────────────────────────────────

  static Future<List<({String category, String code, String title})>> dictionaries({String? category}) async {
    final response = await _api.get<Map<String, dynamic>>('/dictionaries');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] as List : data;
    return _list(raw)
        .map((item) => (
              category: item['category']?.toString() ?? '',
              code: item['code']?.toString() ?? '',
              title: item['title_ru']?.toString() ?? '',
            ))
        .where((item) => item.code.isNotEmpty && (category == null || item.category == category))
        .toList();
  }

  // ── Profile extras ────────────────────────────────────────────────────────

  static Future<FitUser> uploadAvatar(String filePath) async {
    final form = FormData.fromMap({
      'file': await multipartImageFromPath(filePath, filename: 'avatar.jpg'),
    });
    final response = await _api.postMultipart<Map<String, dynamic>>('/me/avatar', data: form);
    return fitUserFromJson(_asMap(_unwrap(response.data)));
  }

  static Future<Map<String, dynamic>> notificationPreferences() async {
    final response = await _api.get<Map<String, dynamic>>('/me/notification-preferences');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> patchNotificationPreferences(Map<String, bool> values) async {
    final response = await _api.patch<Map<String, dynamic>>('/me/notification-preferences', data: values);
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> patchTrainerProfile(Map<String, dynamic> body) async {
    final response = await _api.patch<Map<String, dynamic>>('/trainer/profile', data: body);
    return _asMap(_unwrap(response.data));
  }

  // ── Calendar CRUD ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> calendarEvent(int id) async {
    final response = await _api.get<Map<String, dynamic>>('/trainer/calendar/$id');
    return _asMap(_unwrap(response.data));
  }

  static void _invalidateCalendar() => FitCache.I.invalidate('trainer.calendar');

  static Future<Map<String, dynamic>> createCalendarEvent(Map<String, dynamic> body) async {
    final response = await _api.post<Map<String, dynamic>>('/trainer/calendar', data: body);
    _invalidateCalendar();
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> updateCalendarEvent(int id, Map<String, dynamic> body) async {
    final response = await _api.patch<Map<String, dynamic>>('/trainer/calendar/$id', data: body);
    _invalidateCalendar();
    return _asMap(_unwrap(response.data));
  }

  static Future<void> cancelCalendarEvent(int id) async {
    await _api.post<dynamic>('/trainer/calendar/$id/cancel');
    _invalidateCalendar();
  }

  static Future<void> noShowCalendarEvent(int id) async {
    await _api.post<dynamic>('/trainer/calendar/$id/no-show');
    _invalidateCalendar();
  }

  static Future<void> deleteCalendarEvent(int id) async {
    await _api.delete<dynamic>('/trainer/calendar/$id');
    _invalidateCalendar();
  }

  static Future<Map<String, dynamic>> startSessionFromCalendar(int eventId) async {
    final response = await _api.post<Map<String, dynamic>>('/trainer/calendar/$eventId/start-session');
    _invalidateCalendar();
    return _asMap(_unwrap(response.data));
  }

  // ── Live session ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> session(int id) async {
    final response = await _api.get<Map<String, dynamic>>('/sessions/$id');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> clientSession(int id) async {
    final response = await _api.get<Map<String, dynamic>>('/client/sessions/$id');
    return _asMap(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> exercises({
    String? q,
    String? muscle,
    String? equipment,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/exercises',
      queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        if (muscle != null && muscle.isNotEmpty) 'muscle': muscle,
        if (equipment != null && equipment.isNotEmpty) 'equipment': equipment,
        'page': 1,
        'page_size': 100,
      },
    );
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<Map<String, dynamic>> addSessionExercise(
    int sessionId, {
    required int exerciseId,
    int? restSec,
    int? sets,
    int? reps,
  }) async {
    final response = await _api.post<Map<String, dynamic>>('/sessions/$sessionId/exercises', data: {
      'exercise_id': exerciseId,
      if (restSec != null) 'rest_sec': restSec,
      if (sets != null) 'sets': sets,
      if (reps != null) 'reps': reps,
    });
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> deleteSessionExercise(int sessionId, int seId) async {
    final response = await _api.delete<Map<String, dynamic>>('/sessions/$sessionId/exercises/$seId');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> completeSessionExercise(int sessionId, int seId) async {
    final response = await _api.post<Map<String, dynamic>>('/sessions/$sessionId/exercises/$seId/complete');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> addSessionSet(
    int sessionId,
    int seId, {
    num? weightKg,
    int? reps,
    bool isWarmup = false,
    String? clientOpId,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/sessions/$sessionId/exercises/$seId/sets',
      data: {
        if (weightKg != null) 'weight_kg': weightKg,
        if (reps != null) 'reps': reps,
        'is_warmup': isWarmup,
        if (clientOpId != null && clientOpId.isNotEmpty) 'client_op_id': clientOpId,
      },
    );
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> patchSessionSet(
    int sessionId,
    int setId, {
    num? weightKg,
    int? reps,
    bool? isWarmup,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/sessions/$sessionId/sets/$setId',
      data: {
        if (weightKg != null) 'weight_kg': weightKg,
        if (reps != null) 'reps': reps,
        if (isWarmup != null) 'is_warmup': isWarmup,
      },
    );
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> deleteSessionSet(int sessionId, int setId) async {
    final response = await _api.delete<Map<String, dynamic>>('/sessions/$sessionId/sets/$setId');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> addSessionClient(int sessionId, int clientId) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/sessions/$sessionId/clients',
      data: {'client_id': clientId},
    );
    return _asMap(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> previousExerciseSets(int sessionId, int exerciseId, {int? clientId}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/sessions/$sessionId/previous/$exerciseId',
      queryParameters: {if (clientId != null) 'client_id': clientId},
    );
    final data = _unwrap(response.data);
    if (data is List) return _list(data);
    final map = _asMap(data);
    return _list(map['sets'] ?? map['items'] ?? map['previous']);
  }

  static Future<void> completeSession(int sessionId) async {
    await _api.post<dynamic>('/sessions/$sessionId/complete');
  }

  static Future<Map<String, dynamic>> pauseSession(int sessionId) async {
    final response = await _api.post<Map<String, dynamic>>('/sessions/$sessionId/pause');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> resumeSession(int sessionId) async {
    final response = await _api.post<Map<String, dynamic>>('/sessions/$sessionId/resume');
    return _asMap(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> strengthProgress({int? linkId}) async {
    final path = linkId == null ? '/client/strength-progress' : '/trainer/clients/$linkId/strength-progress';
    final response = await _api.get<Map<String, dynamic>>(path);
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<Map<String, dynamic>> volumeProgress({int days = 30}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/client/volume-progress',
      queryParameters: {'days': days},
    );
    return _asMap(_unwrap(response.data));
  }

  // ── Client card extras ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> patchClientLink(int linkId, Map<String, dynamic> body) async {
    final response = await _api.patch<Map<String, dynamic>>('/trainer/clients/$linkId', data: body);
    return _asMap(_unwrap(response.data));
  }

  static Future<void> archiveClientLink(int linkId) async {
    await _api.delete<dynamic>('/trainer/clients/$linkId');
  }

  static Future<Map<String, dynamic>> addLinkMeasurement(int linkId, Map<String, num> body) async {
    final response = await _api.post<Map<String, dynamic>>('/trainer/clients/$linkId/measurements', data: body);
    return _asMap(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> linkNotes(int linkId) async {
    final response = await _api.get<Map<String, dynamic>>('/trainer/clients/$linkId/notes');
    return _list(_unwrap(response.data));
  }

  static Future<void> addLinkNote(int linkId, String text) async {
    await _api.post<dynamic>('/trainer/clients/$linkId/notes', data: {'text': text});
  }

  static Future<void> deleteLinkNote(int linkId, int noteId) async {
    await _api.delete<dynamic>('/trainer/clients/$linkId/notes/$noteId');
  }

  // ── Trainer requests ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> trainerRequests({String status = 'pending'}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/trainer/requests',
      queryParameters: {'status': status, 'page': 1, 'page_size': 50},
    );
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<void> acceptRequest(int id) async {
    await _api.post<dynamic>('/trainer/requests/$id/accept');
    _invalidateTrainerCaches();
  }

  static Future<void> rejectRequest(int id) async {
    await _api.post<dynamic>('/trainer/requests/$id/reject');
    _invalidateTrainerCaches();
  }

  static Future<List<Map<String, dynamic>>> myTrainerRequests({String? status}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/me/trainer-requests',
      queryParameters: {if (status != null) 'status': status},
    );
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  // ── Programs extras ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> program(int id) async {
    final response = await _api.get<Map<String, dynamic>>('/programs/$id');
    return _asMap(_unwrap(response.data));
  }

  static Future<void> saveProgram(int id) async {
    await _api.post<dynamic>('/programs/$id/save');
  }

  static Future<void> unsaveProgram(int id) async {
    await _api.delete<dynamic>('/programs/$id/save');
  }

  static Future<Map<String, dynamic>> duplicateProgram(int id) async {
    final response = await _api.post<Map<String, dynamic>>('/programs/$id/duplicate');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> createProgram(Map<String, dynamic> body) async {
    final response = await _api.post<Map<String, dynamic>>('/programs', data: body);
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> uploadProgramCover(int programId, String filePath, {bool clear = false}) async {
    final form = FormData.fromMap({
      if (!clear) 'file': await multipartImageFromPath(filePath, filename: 'cover.jpg'),
      'clear': clear ? 'true' : 'false',
    });
    final response = await _api.postMultipart<Map<String, dynamic>>('/programs/$programId/cover', data: form);
    FitCache.I.invalidate('programs');
    return _asMap(_unwrap(response.data));
  }

  static Future<void> deleteProgram(int id) async {
    await _api.delete<dynamic>('/programs/$id');
    FitCache.I.invalidate('programs');
  }

  static Future<Map<String, dynamic>> addProgramDay(int programId, Map<String, dynamic> body) async {
    final response = await _api.post<Map<String, dynamic>>('/programs/$programId/days', data: body);
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> patchProgramDay(int programId, int dayId, Map<String, dynamic> body) async {
    final response = await _api.patch<Map<String, dynamic>>('/programs/$programId/days/$dayId', data: body);
    FitCache.I.invalidate('programs');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> deleteProgramDay(int programId, int dayId) async {
    final response = await _api.delete<Map<String, dynamic>>('/programs/$programId/days/$dayId');
    FitCache.I.invalidate('programs');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> addProgramDayExercise(int programId, int dayId, Map<String, dynamic> body) async {
    final response = await _api.post<Map<String, dynamic>>('/programs/$programId/days/$dayId/exercises', data: body);
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> patchProgramDayExercise(
    int programId,
    int dayId,
    int itemId,
    Map<String, dynamic> body,
  ) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/programs/$programId/days/$dayId/exercises/$itemId',
      data: body,
    );
    FitCache.I.invalidate('programs');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> deleteProgramDayExercise(int programId, int dayId, int itemId) async {
    final response = await _api.delete<Map<String, dynamic>>(
      '/programs/$programId/days/$dayId/exercises/$itemId',
    );
    FitCache.I.invalidate('programs');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> reorderProgramDayExercises(
    int programId,
    int dayId,
    List<int> itemIds,
  ) async {
    final response = await _api.put<Map<String, dynamic>>(
      '/programs/$programId/days/$dayId/exercises/reorder',
      data: {'item_ids': itemIds},
    );
    FitCache.I.invalidate('programs');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> addProgramWeek(int programId, {String? title, int? weekIndex, bool isPreview = false}) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/programs/$programId/weeks',
      data: {
        if (title != null && title.isNotEmpty) 'title': title,
        if (weekIndex != null) 'week_index': weekIndex,
        'is_preview': isPreview,
      },
    );
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> deleteProgramWeek(int programId, int weekId) async {
    final response = await _api.delete<Map<String, dynamic>>('/programs/$programId/weeks/$weekId');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> duplicateProgramWeek(int programId, int weekId) async {
    final response = await _api.post<Map<String, dynamic>>('/programs/$programId/weeks/$weekId/duplicate');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> submitProgram(int programId) async {
    final response = await _api.post<Map<String, dynamic>>('/programs/$programId/submit');
    return _asMap(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> assignProgram(
    int programId, {
    int? linkId,
    List<int>? linkIds,
    String? note,
  }) async {
    final ids = <int>[
      ...?linkIds,
      if (linkId != null && linkId > 0) linkId,
    ];
    final unique = <int>{for (final id in ids) if (id > 0) id}.toList();
    if (unique.isEmpty) {
      throw ArgumentError('linkId or linkIds required');
    }
    final response = await _api.post<Map<String, dynamic>>(
      '/programs/$programId/assign',
      data: {
        if (unique.length == 1) 'link_id': unique.first,
        'link_ids': unique,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    final data = _unwrap(response.data);
    if (data is List) return _list(data);
    return [_asMap(data)];
  }

  static Future<void> revokeProgramAssignment(int assignmentId) async {
    await _api.delete<dynamic>('/trainer/program-assignments/$assignmentId');
  }

  static Future<List<Map<String, dynamic>>> myAssignedPrograms() async {
    final response = await _api.get<Map<String, dynamic>>('/me/assigned-programs');
    return _list(_unwrap(response.data));
  }

  /// Own workout complexes (drafts + published) for current user.
  static Future<List<Map<String, dynamic>>> myOwnPrograms({bool force = false}) {
    return FitCache.I.get<List<Map<String, dynamic>>>(
      key: 'me|programs',
      force: force,
      freshFor: const Duration(seconds: 30),
      keepFor: const Duration(hours: 12),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>(
          '/me/programs',
          queryParameters: {'page': 1, 'page_size': 50},
        );
        final data = _unwrap(response.data);
        final raw = data is Map && data['items'] is List ? data['items'] : data;
        return _list(raw);
      },
    );
  }

  /// Figma «Сохраненные тренировки» — programs saved by current user.
  static Future<List<Map<String, dynamic>>> savedPrograms() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/me/saved-programs',
      queryParameters: {'page': 1, 'page_size': 50},
    );
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<List<Map<String, dynamic>>> trainerPrograms({String? status}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/trainer/programs',
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        'page': 1,
        'page_size': 50,
      },
    );
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  // ── Trainers marketplace ──────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> trainers({
    String? q,
    String? category,
    String sort = 'rating',
    bool force = false,
  }) {
    final key = 'trainers|$q|$category|$sort';
    return FitCache.I.get<List<Map<String, dynamic>>>(
      key: key,
      force: force,
      freshFor: const Duration(minutes: 2),
      keepFor: const Duration(hours: 24),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>(
          '/trainers',
          queryParameters: {
            if (q != null && q.isNotEmpty) 'q': q,
            if (category != null) 'category': category,
            'sort': sort,
            'page': 1,
            'page_size': 30,
          },
        );
        final data = _unwrap(response.data);
        final raw = data is Map && data['items'] is List ? data['items'] : data;
        return _list(raw);
      },
    );
  }

  static Future<Map<String, dynamic>> trainerPublic(int id, {bool force = false}) {
    return FitCache.I.get<Map<String, dynamic>>(
      key: 'trainer.public.$id',
      force: force,
      freshFor: const Duration(minutes: 5),
      keepFor: const Duration(hours: 24),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>('/trainers/$id');
        return _asMap(_unwrap(response.data));
      },
    );
  }

  static Future<List<Map<String, dynamic>>> trainerReviews(int id) async {
    final response = await _api.get<Map<String, dynamic>>('/trainers/$id/reviews');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<void> postTrainerReview(
    int id, {
    required num rating,
    String text = '',
    bool isAnonymous = false,
  }) async {
    await _api.post<dynamic>(
      '/trainers/$id/reviews',
      data: {
        'rating': rating,
        'text': text,
        'is_anonymous': isAnonymous,
      },
    );
  }

  static Future<void> bookmarkTrainer(int id) async {
    await _api.post<dynamic>('/trainers/$id/bookmark');
  }

  static Future<void> unbookmarkTrainer(int id) async {
    await _api.delete<dynamic>('/trainers/$id/bookmark');
  }

  static Future<List<Map<String, dynamic>>> trainerBookmarks() async {
    final response = await _api.get<Map<String, dynamic>>('/me/trainer-bookmarks');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<void> requestTrainer(int trainerId) async {
    await _api.post<dynamic>('/trainers/$trainerId/request');
  }

  // ── Measurements / photos / notes ─────────────────────────────────────────

  static Future<Map<String, dynamic>> createMeasurement(Map<String, num> body) async {
    final response = await _api.post<Map<String, dynamic>>('/client/measurements', data: body);
    _invalidateMeasurementCaches();
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> patchMeasurement(int id, Map<String, num> body) async {
    final response = await _api.patch<Map<String, dynamic>>('/client/measurements/$id', data: body);
    _invalidateMeasurementCaches();
    return _asMap(_unwrap(response.data));
  }

  /// Upload one photo-progress set: up to 3 images (`front,side,back`).
  /// HEIC/HEIF (iPhone) and other formats are converted to JPEG/PNG first.
  static Future<Map<String, dynamic>> uploadPhotoProgress({
    required String takenOn,
    required List<String> filePaths,
    List<String> angles = const ['front', 'side', 'back'],
  }) async {
    if (filePaths.isEmpty) {
      throw ArgumentError('files required');
    }
    final paths = filePaths.take(3).toList();
    final angleList = angles.take(paths.length).toList();
    while (angleList.length < paths.length) {
      angleList.add(['front', 'side', 'back'][angleList.length]);
    }
    final form = FormData();
    form.fields.add(MapEntry('taken_on', takenOn));
    form.fields.add(MapEntry('angles', angleList.join(',')));
    for (var i = 0; i < paths.length; i++) {
      form.files.add(
        MapEntry('files', await multipartImageFromPath(paths[i], filename: angleList[i])),
      );
    }
    final response = await _api.postMultipart<Map<String, dynamic>>('/client/photo-progress', data: form);
    FitCache.I.invalidateAll(const ['photo-progress', 'progress', 'home']);
    return _asMap(_unwrap(response.data));
  }

  static Future<void> deleteNote(int id) async {
    await _api.delete<dynamic>('/client/notes/$id');
  }

  // ── Support / billing extras ──────────────────────────────────────────────

  static Future<void> createSupportTicket({required String subject, required String message}) async {
    await _api.post<dynamic>('/support/tickets', data: {'subject': subject, 'message': message});
  }

  static Future<List<Map<String, dynamic>>> supportTickets() async {
    final response = await _api.get<Map<String, dynamic>>('/support/tickets');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<Map<String, dynamic>> patchSubscription({int? planId, bool? autoRenew}) async {
    final response = await _api.patch<Map<String, dynamic>>('/me/subscription', data: {
      if (planId != null) 'plan_id': planId,
      if (autoRenew != null) 'auto_renew': autoRenew,
    });
    return _asMap(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> paymentMethods() async {
    final response = await _api.get<Map<String, dynamic>>('/me/payment-methods');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  // ── Video lessons ─────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> videoCategories({bool force = false}) {
    return FitCache.I.get<List<Map<String, dynamic>>>(
      key: 'categories',
      force: force,
      freshFor: const Duration(minutes: 10),
      keepFor: const Duration(hours: 6),
      fetch: () async {
        final response = await _api.get<Map<String, dynamic>>('/categories');
        final data = _unwrap(response.data);
        final raw = data is Map && data['items'] is List ? data['items'] : data;
        return _list(raw);
      },
    );
  }

  static Future<Map<String, dynamic>> videoCategory(int id) async {
    final response = await _api.get<Map<String, dynamic>>('/categories/$id');
    return _asMap(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> categoryTopics(int categoryId) async {
    final response = await _api.get<Map<String, dynamic>>('/categories/$categoryId/topics');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<List<Map<String, dynamic>>> topicVideos(int topicId) async {
    final response = await _api.get<Map<String, dynamic>>('/topics/$topicId/videos');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<List<Map<String, dynamic>>> videos({
    int? categoryId,
    int? topicId,
    int? trainerId,
    String? level,
    String? search,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/videos',
      queryParameters: {
        if (categoryId != null) 'category_id': categoryId,
        if (topicId != null) 'topic_id': topicId,
        if (trainerId != null) 'trainer_id': trainerId,
        if (level != null && level.isNotEmpty) 'level': level,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': 1,
        'page_size': 50,
      },
    );
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<Map<String, dynamic>> video(int id) async {
    final response = await _api.get<Map<String, dynamic>>('/videos/$id');
    return _asMap(_unwrap(response.data));
  }

  static Future<List<Map<String, dynamic>>> trainerPublicVideos(int trainerId) async {
    final response = await _api.get<Map<String, dynamic>>('/trainers/$trainerId/videos');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<List<Map<String, dynamic>>> myTrainerVideos({String? status}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/trainer/videos',
      queryParameters: {if (status != null && status.isNotEmpty) 'status': status},
    );
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<Map<String, dynamic>> createTrainerVideo({
    required String title,
    required int categoryId,
    required int topicId,
    String? description,
    String? level,
    int? durationSeconds,
    String? videoUrl,
    bool submit = false,
    String? videoPath,
    String? thumbnailPath,
  }) async {
    final map = <String, dynamic>{
      'title': title,
      'category_id': categoryId,
      'topic_id': topicId,
      if (description != null && description.isNotEmpty) 'description': description,
      if (level != null && level.isNotEmpty) 'level': level,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (videoUrl != null && videoUrl.isNotEmpty) 'video_url': videoUrl,
      'submit': submit ? 'true' : 'false',
    };
    if (videoPath != null && videoPath.isNotEmpty) {
      map['video'] = await MultipartFile.fromFile(videoPath, filename: videoPath.split('/').last);
    }
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      map['thumbnail'] = await multipartImageFromPath(thumbnailPath, filename: 'thumbnail.jpg');
    }
    final form = FormData.fromMap(map);
    final response = await _api.postMultipart<Map<String, dynamic>>('/trainer/videos', data: form);
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> updateTrainerVideo(
    int id, {
    String? title,
    int? categoryId,
    int? topicId,
    String? description,
    String? level,
    String? videoUrl,
    String? videoPath,
    String? thumbnailPath,
  }) async {
    final map = <String, dynamic>{
      if (title != null) 'title': title,
      if (categoryId != null) 'category_id': categoryId,
      if (topicId != null) 'topic_id': topicId,
      if (description != null) 'description': description,
      if (level != null) 'level': level,
      if (videoUrl != null) 'video_url': videoUrl,
    };
    if (videoPath != null && videoPath.isNotEmpty) {
      map['video'] = await MultipartFile.fromFile(videoPath, filename: videoPath.split('/').last);
    }
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      map['thumbnail'] = await multipartImageFromPath(thumbnailPath, filename: 'thumbnail.jpg');
    }
    final form = FormData.fromMap(map);
    final response = await _api.patch<Map<String, dynamic>>(
      '/trainer/videos/$id',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return _asMap(_unwrap(response.data));
  }

  static Future<void> submitTrainerVideo(int id) async {
    await _api.post<dynamic>('/trainer/videos/$id/submit');
  }

  static Future<void> deleteTrainerVideo(int id) async {
    await _api.delete<dynamic>('/trainer/videos/$id');
  }

  static Future<List<Map<String, dynamic>>> clientAssignedVideos(int linkId) async {
    final response = await _api.get<Map<String, dynamic>>('/trainer/clients/$linkId/videos');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<void> assignVideosToClient(int linkId, List<int> videoIds) async {
    await _api.post<dynamic>('/trainer/clients/$linkId/videos', data: {'video_ids': videoIds});
  }

  static Future<void> unassignClientVideo(int linkId, int assignmentId) async {
    await _api.delete<dynamic>('/trainer/clients/$linkId/videos/$assignmentId');
  }

  static Future<List<Map<String, dynamic>>> myAssignedVideos() async {
    final response = await _api.get<Map<String, dynamic>>('/me/assigned-videos');
    final data = _unwrap(response.data);
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    return _list(raw);
  }

  static Future<Map<String, dynamic>> myAssignedVideo(int assignmentId) async {
    final response = await _api.get<Map<String, dynamic>>('/me/assigned-videos/$assignmentId');
    return _asMap(_unwrap(response.data));
  }

  static Future<Map<String, dynamic>> myAccessibleVideo(int id) async {
    final response = await _api.get<Map<String, dynamic>>('/me/videos/$id');
    return _asMap(_unwrap(response.data));
  }

  static Future<FitUser> _saveSession(Map<String, dynamic>? body) async {
    final data = _asMap(_unwrap(body));
    final access = data['access_token']?.toString();
    final refresh = data['refresh_token']?.toString();
    if (access != null && access.isNotEmpty) await _storage.saveToken(access);
    if (refresh != null && refresh.isNotEmpty) await _storage.saveRefreshToken(refresh);
    return fitUserFromJson(_asMap(data['user']));
  }
}

dynamic _unwrap(dynamic body) {
  if (body is Map && body.containsKey('data')) return body['data'];
  return body;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is List) {
    return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }
  return const [];
}

int _int(Object? value) => int.tryParse('$value') ?? 0;

List<String> _strings(Object? value) {
  if (value is List) return value.map((item) => item.toString()).toList();
  return const [];
}

String _personName(Map<String, dynamic> json) {
  final first = json['first_name']?.toString() ?? json['name']?.toString() ?? '';
  final last = json['last_name']?.toString() ?? json['surname']?.toString() ?? '';
  final full = '$first $last'.trim();
  return full.isEmpty ? 'Клиент' : full;
}

String _formatLabel(String format) {
  return switch (format) {
    'online' => 'Онлайн',
    'gym' => 'Зал',
    'hybrid' => 'Гибрид',
    'home' => 'Дом',
    'visit' => 'Выезд',
    _ => format.isEmpty ? 'Зал' : format,
  };
}

String _statusLabel(String status) {
  return switch (status) {
    'completed' => 'Завершено',
    'in_progress' => 'В процессе',
    'cancelled' => 'Отменено',
    'no_show' => 'Неявка',
    _ => 'Ожидает',
  };
}

String _kindLabel(String code) => FitLabels.kind(code);

String _muscleLabel(String code) => FitLabels.muscle(code);

String _hhmm(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _dateLabel(String? raw) => DateHelper.formatRuAny(raw, withTime: false, fallback: '');
