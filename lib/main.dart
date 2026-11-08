import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainhub/app.dart';
import 'package:trainhub/core/config/env_config.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/logger/app_logger.dart';
import 'package:trainhub/features/fitpro/fit_cache.dart';
import 'package:trainhub/features/fitpro/workout_offline_queue.dart';

/// Application entry point.
///
/// Boot order:
/// 1. Initialize environment (`--dart-define=ENV=...`)
/// 2. Register GetIt dependencies
/// 3. Hydrate durable FitCache + flush offline workout queue
/// 4. Run the app inside a [ProviderScope]
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  EnvConfig.init();
  await setupDependencyInjection();
  await FitCache.I.hydrate();
  // Best-effort: sync any queued live-workout ops from previous session.
  // ignore: unawaited_futures
  WorkoutOfflineQueue.I.flush();

  AppLogger.i('Starting ${EnvConfig.appName} (${EnvConfig.environment.name})');

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
