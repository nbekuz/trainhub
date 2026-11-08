import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/utils/ru_phone.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/services/local_storage/storage_service.dart';

enum FitRole { trainer, client }

class FitClient {
  const FitClient({
    required this.id,
    required this.name,
    required this.surname,
    required this.uuid,
    this.goals = 0,
    this.place = 'Зал',
    this.online = false,
    this.isNew = false,
    this.isMale = true,
    this.phone,
    this.userId = 0,
  });

  final int id;
  final int userId;
  final String name;
  final String surname;
  final String uuid;
  final int goals;
  final String place;
  final bool online;
  final bool isNew;
  final bool isMale;
  final String? phone;

  String get initials {
    final a = name.isNotEmpty ? name[0] : '';
    final b = surname.isNotEmpty ? surname[0] : '';
    final value = '$a$b'.toUpperCase();
    return value.isEmpty ? 'U' : value;
  }
}

class FitUser {
  const FitUser({
    required this.id,
    required this.name,
    required this.surname,
    required this.email,
    required this.uuid,
    required this.role,
    this.avatarUrl,
    this.phone,
    this.whatsapp,
    this.telegram,
    this.gender,
    this.birthDate,
    this.heightCm,
    this.weightGoalKg,
    this.measurements = const [],
  });

  final int id;
  final String name;
  final String surname;
  final String email;
  final String uuid;
  final FitRole role;
  final String? avatarUrl;
  final String? phone;
  final String? whatsapp;
  final String? telegram;
  final String? gender;
  final String? birthDate;
  final String? heightCm;
  final String? weightGoalKg;
  final List<Map<String, dynamic>> measurements;

  bool get profileComplete {
    final phoneOk = RuPhone.nationalDigits(phone).length >= 10;
    return phoneOk &&
        _filled(gender) &&
        _filled(birthDate) &&
        _filled(heightCm) &&
        _filled(weightGoalKg);
  }

  String get initials {
    final a = name.isNotEmpty ? name[0] : '';
    final b = surname.isNotEmpty ? surname[0] : '';
    final value = '$a$b'.toUpperCase();
    return value.isEmpty ? 'U' : value;
  }
}

bool _filled(String? value) {
  final text = value?.trim() ?? '';
  return text.isNotEmpty && text != 'null';
}

FitRole fitRoleFrom(Object? raw) {
  if (raw is List) {
    return raw.map((item) => item.toString()).contains('trainer') ? FitRole.trainer : FitRole.client;
  }
  return raw.toString().toLowerCase() == 'trainer' ? FitRole.trainer : FitRole.client;
}

FitUser fitUserFromJson(Map<String, dynamic> json) {
  final measurements = json['measurements'];
  return FitUser(
    id: int.tryParse('${json['id']}') ?? 0,
    name: json['first_name']?.toString() ?? json['name']?.toString() ?? '',
    surname: json['last_name']?.toString() ?? json['surname']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    uuid: json['public_id']?.toString() ?? json['uuid']?.toString() ?? '',
    role: fitRoleFrom(json['roles'] ?? json['role']),
    avatarUrl: json['avatar_url']?.toString(),
    phone: json['phone']?.toString(),
    whatsapp: json['whatsapp']?.toString(),
    telegram: json['telegram']?.toString(),
    gender: json['gender']?.toString(),
    birthDate: json['birth_date']?.toString(),
    heightCm: json['height_cm']?.toString(),
    weightGoalKg: json['weight_goal_kg']?.toString(),
    measurements: measurements is List
        ? measurements.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : const [],
  );
}

FitClient fitClientFromJson(Map<String, dynamic> json) {
  final format = json['training_format']?.toString() ?? '';
  final gender = json['gender']?.toString();
  return FitClient(
    id: int.tryParse('${json['id'] ?? json['user_id']}') ?? 0,
    name: json['first_name']?.toString() ?? json['name']?.toString() ?? '',
    surname: json['last_name']?.toString() ?? json['surname']?.toString() ?? '',
    uuid: json['public_id']?.toString() ?? json['uuid']?.toString() ?? '',
    goals: int.tryParse('${json['goals_count'] ?? 0}') ?? 0,
    place: switch (format) {
      'online' => 'Онлайн',
      'hybrid' => 'Гибрид',
      'home' => 'Дом',
      'visit' => 'Выезд',
      _ => 'Зал',
    },
    online: format == 'online',
    isNew: json['status']?.toString() == 'new',
    isMale: gender != 'female',
    phone: json['phone']?.toString(),
    userId: int.tryParse('${json['user_id'] ?? json['client_id'] ?? json['id']}') ?? 0,
  );
}

class FitSession {
  const FitSession({
    this.user,
    this.pendingEmail = '',
    this.pendingName = '',
    this.pendingRole,
    this.clients = const [],
  });

  final FitUser? user;
  final String pendingEmail;
  final String pendingName;
  final FitRole? pendingRole;
  final List<FitClient> clients;
}

class FitSessionNotifier extends Notifier<FitSession> {
  @override
  FitSession build() => const FitSession();

  Future<bool> restore() async {
    final token = getIt<StorageService>().getToken();
    if (token == null || token.isEmpty) return false;
    try {
      final user = await FitApi.me();
      state = FitSession(user: user);
      return true;
    } catch (_) {
      await getIt<StorageService>().clearAuth();
      return false;
    }
  }

  void setPending({
    required String email,
    String name = '',
    FitRole? role,
  }) {
    state = FitSession(
      user: state.user,
      pendingEmail: email,
      pendingName: name,
      pendingRole: role ?? state.pendingRole,
      clients: state.clients,
    );
  }

  void signIn(FitUser user) {
    state = FitSession(user: user, clients: state.clients);
  }

  Future<void> logout() async {
    try {
      await FitApi.logout();
    } catch (_) {
      await getIt<StorageService>().clearAuth();
    }
    state = const FitSession();
  }

  /// Clears in-memory session after tokens were already wiped by the network layer.
  void invalidateLocal() {
    state = const FitSession();
  }

  void setClients(List<FitClient> clients) {
    state = FitSession(user: state.user, clients: clients, pendingEmail: state.pendingEmail, pendingName: state.pendingName, pendingRole: state.pendingRole);
  }
}

final fitSessionProvider =
    NotifierProvider<FitSessionNotifier, FitSession>(FitSessionNotifier.new);
