import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/core/config/app_config.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/network/auth_session.dart';
import 'package:trainhub/core/theme/app_theme.dart';
import 'package:trainhub/core/theme/theme_provider.dart';
import 'package:trainhub/features/fitpro/fit_cache.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/active_workout_overlay.dart';
import 'package:trainhub/features/fitpro/workout_offline_queue.dart';
import 'package:trainhub/routes/app_router.dart';
import 'package:trainhub/routes/route_names.dart';
import 'package:trainhub/services/navigation/navigation_service.dart';

/// Provides a single [GoRouter] instance for the app lifetime.
final appRouterProvider = Provider<GoRouter>((ref) => createAppRouter());

/// Root application widget.
///
/// Wires theme mode (Riverpod) and navigation (GoRouter).
class App extends ConsumerStatefulWidget {
  /// Creates the root [App] widget.
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    getIt<AuthSession>().bind(() {
      ref.read(fitSessionProvider.notifier).invalidateLocal();
      unawaited(FitCache.I.clear());
      getIt<NavigationService>().go(RouteNames.login);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    getIt<AuthSession>().unbind();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(WorkoutOfflineQueue.I.flush());
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) => ActiveWorkoutOverlay(
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
