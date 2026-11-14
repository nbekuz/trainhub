import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/routes/route_names.dart';

class FitShell extends StatefulWidget {
  const FitShell({
    super.key,
    required this.navigationShell,
    required this.trainer,
  });

  final StatefulNavigationShell navigationShell;
  final bool trainer;

  static const _assets = [
    'assets/icons/navbar/home.svg',
    'assets/icons/navbar/calendar.svg',
    'assets/icons/navbar/dumbbel.svg',
    'assets/icons/navbar/time.svg',
    'assets/icons/navbar/user.svg',
  ];

  static const double barHeight = 70;
  static const double iosBottomGap = 34;
  static const double _radius = 40;

  /// Tab that was open before an inner page was pushed; [FitPageShell] keeps it highlighted.
  static int lastIndex = 0;

  /// Gap from navbar bottom edge to the physical screen bottom.
  /// iOS: always 34pt (home indicator clearance). Android: unchanged.
  static double bottomGap(BuildContext context) {
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (isIos) return iosBottomGap;
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return inset > 0 ? inset : 8.0;
  }

  /// Total space reserved under scroll content for the floating bar.
  static double contentClearance(BuildContext context, {double extra = 24}) {
    return barHeight + extra + bottomGap(context);
  }

  @override
  State<FitShell> createState() => _FitShellState();
}

class _FitShellState extends State<FitShell> {
  @override
  Widget build(BuildContext context) {
    FitShell.lastIndex = widget.navigationShell.currentIndex;
    return Scaffold(
      backgroundColor: AppColors.fitBg,
      body: widget.navigationShell,
      extendBody: true,
      bottomNavigationBar: FitNavBar(
        currentIndex: widget.navigationShell.currentIndex,
        onTap: (index) => widget.navigationShell.goBranch(index),
      ),
    );
  }
}

/// Wraps pages opened on top of the tabs so the bottom menu stays visible.
class FitPageShell extends ConsumerWidget {
  const FitPageShell({super.key, required this.child});

  final Widget child;

  static const _trainerTabs = [
    RouteNames.trainer,
    RouteNames.trainerCalendar,
    RouteNames.trainerWorkouts,
    RouteNames.trainerTimer,
    RouteNames.trainerProfile,
  ];
  static const _clientTabs = [
    RouteNames.client,
    RouteNames.clientCalendar,
    RouteNames.clientWorkouts,
    RouteNames.clientTimer,
    RouteNames.clientProfile,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(fitSessionProvider).user?.role;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final showBar = role != null && !keyboardOpen;
    final tabs = role == FitRole.trainer ? _trainerTabs : _clientTabs;
    return Scaffold(
      backgroundColor: AppColors.fitBg,
      // The page's own Scaffold handles the keyboard; the bar hides while typing.
      resizeToAvoidBottomInset: false,
      body: child,
      bottomNavigationBar: showBar
          ? FitNavBar(currentIndex: FitShell.lastIndex, onTap: (index) => context.go(tabs[index]))
          : null,
    );
  }
}

class FitNavBar extends StatelessWidget {
  const FitNavBar({super.key, required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottomPad = FitShell.bottomGap(context);
    final totalHeight = FitShell.barHeight + bottomPad;

    return SizedBox(
      height: totalHeight,
      width: double.infinity,
      child: Stack(
        children: [
          // Blur from navbar top edge down to the screen bottom.
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF0D0D0D).withValues(alpha: 0.18),
                          const Color(0xFF0D0D0D).withValues(alpha: 0.42),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 16,
            right: 16,
            height: FitShell.barHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(FitShell._radius),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: List.generate(5, (index) {
                  final selected = currentIndex == index;
                  final color = index == 2
                      ? Colors.black
                      : selected
                          ? AppColors.accent
                          : AppColors.fitGrey;
                  final icon = SvgPicture.asset(
                    FitShell._assets[index],
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  );
                  if (index == 2) {
                    return Expanded(
                      child: Center(
                        child: GestureDetector(
                          onTap: () => onTap(index),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                            child: Center(child: icon),
                          ),
                        ),
                      ),
                    );
                  }
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(index),
                      child: Center(child: icon),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
