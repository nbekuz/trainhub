import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/core/network/api_client.dart';
import 'package:trainhub/core/network/api_service.dart';
import 'package:trainhub/core/network/auth_session.dart';
import 'package:trainhub/services/api/user_api_service.dart';
import 'package:trainhub/services/local_storage/storage_service.dart';
import 'package:trainhub/services/navigation/navigation_service.dart';

/// Global service locator instance.
final GetIt getIt = GetIt.instance;

/// Registers all app-wide dependencies with GetIt.
///
/// Call once from `main()` before `runApp`.
Future<void> setupDependencyInjection() async {
  final prefs = await SharedPreferences.getInstance();
  final navigatorKey = GlobalKey<NavigatorState>();

  getIt
    ..registerLazySingleton<SharedPreferences>(() => prefs)
    ..registerLazySingleton<StorageService>(() => StorageService(getIt()))
    ..registerLazySingleton<AuthSession>(AuthSession.new)
    ..registerLazySingleton<GlobalKey<NavigatorState>>(() => navigatorKey)
    ..registerLazySingleton<NavigationService>(
      () => NavigationService(getIt<GlobalKey<NavigatorState>>()),
    )
    ..registerLazySingleton<ApiClient>(() => ApiClient(getIt(), getIt()))
    ..registerLazySingleton<ApiService>(() => ApiService(getIt()))
    ..registerLazySingleton<UserApiService>(() => UserApiService(getIt()));
}
