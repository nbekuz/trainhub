import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/core/constants/app_constants.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/routes/route_names.dart';

/// Initial splash screen shown on cold start.
///
/// Replace the branding / bootstrap logic for each new project.
class SplashPage extends ConsumerStatefulWidget {
  /// Creates the splash page.
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    _navigateNext();
  }

  Future<void> _navigateNext() async {
    final restored = ref.read(fitSessionProvider.notifier).restore();
    await Future<void>.delayed(AppConstants.splashDuration);
    final signedIn = await restored;
    if (!mounted) return;
    if (!signedIn) {
      context.go(RouteNames.welcome);
      return;
    }
    final user = ref.read(fitSessionProvider).user;
    if (user != null && !user.profileComplete) {
      context.go(RouteNames.profileSetup);
      return;
    }
    context.go(user?.role == FitRole.trainer ? RouteNames.trainer : RouteNames.client);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.fitBg),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: const FitLogo(),
            ),
          ),
        ),
      ),
    );
  }
}
