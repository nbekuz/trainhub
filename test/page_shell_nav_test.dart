import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/app.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/shell/fit_shell.dart';
import 'package:trainhub/routes/app_router.dart';
import 'package:trainhub/routes/route_names.dart';

class _Page extends StatelessWidget {
  const _Page(this.title, {this.next});

  final String title;
  final String? next;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text(title),
          if (next != null) TextButton(onPressed: () => context.push(next!), child: Text('open $next')),
          TextField(key: ValueKey('field-$title')),
          TextButton(onPressed: () => context.pop('done'), child: const Text('close')),
        ],
      ),
    );
  }
}

/// Same nesting as `createAppRouter`: tabs in a StatefulShellRoute, inner pages in a ShellRoute.
GoRouter _router() => GoRouter(
      initialLocation: RouteNames.trainer,
      routes: [
        ShellRoute(
          builder: (_, _, child) => FitPageShell(child: child),
          routes: [
            GoRoute(path: RouteNames.clients, builder: (_, _) => const _Page('clients', next: RouteNames.clientDetail)),
            GoRoute(path: RouteNames.clientDetail, builder: (_, _) => const _Page('detail')),
          ],
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => FitShell(navigationShell: shell, trainer: true),
          branches: [
            for (final path in [
              RouteNames.trainer,
              RouteNames.trainerCalendar,
              RouteNames.trainerWorkouts,
              RouteNames.trainerTimer,
              RouteNames.trainerProfile,
            ])
              StatefulShellBranch(
                routes: [GoRoute(path: path, builder: (_, _) => _Page('tab $path', next: RouteNames.clients))],
              ),
          ],
        ),
      ],
    );

Future<GoRouter> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(fitSessionProvider.notifier).signIn(
        const FitUser(id: 1, name: 'Т', surname: '', email: '', uuid: '1', role: FitRole.trainer),
      );
  final router = _router();
  dismissKeyboardOnNavigation(router);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => UnfocusOnTapOutside(child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('Menu stays on pages opened from a tab, through nested pushes', (tester) async {
    await _pump(tester);
    expect(find.byType(FitNavBar), findsOneWidget);

    await tester.tap(find.text('open ${RouteNames.clients}'));
    await tester.pumpAndSettle();
    expect(find.text('clients'), findsOneWidget);
    expect(find.byType(FitNavBar), findsOneWidget);

    await tester.tap(find.text('open ${RouteNames.clientDetail}'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(find.byType(FitNavBar), findsOneWidget);
  });

  testWidgets('Back and push results still work from inner pages', (tester) async {
    final router = await _pump(tester);
    final result = router.push<String>(RouteNames.clients);
    await tester.pumpAndSettle();
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    expect(await result, 'done');
    expect(find.text('tab ${RouteNames.trainer}'), findsOneWidget);
  });

  testWidgets('Tapping a menu tab on an inner page opens that tab', (tester) async {
    final router = await _pump(tester);
    router.push(RouteNames.clients);
    await tester.pumpAndSettle();
    final bar = find.byType(FitNavBar);
    final box = tester.getRect(bar);
    // Calendar is the 2nd of 5 equal slots inside the 16px side insets.
    await tester.tapAt(Offset(16 + (box.width - 32) * 1.5 / 5, box.top + 35));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, RouteNames.trainerCalendar);
    expect(find.text('clients'), findsNothing);
  });

  testWidgets('Menu hides while the keyboard is open', (tester) async {
    final router = await _pump(tester);
    router.push(RouteNames.clients);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.byType(FitNavBar), findsNothing);
  });

  test('The live workout page is shown with the bottom menu', () async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    await setupDependencyInjection();
    final shell = createAppRouter().configuration.routes.whereType<ShellRoute>().single;
    final paths = shell.routes.whereType<GoRoute>().map((r) => r.path);
    expect(paths, contains(RouteNames.liveSession));
  });

  Future<void> focusField(WidgetTester tester, String title) async {
    await tester.tap(find.byKey(ValueKey('field-$title')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
  }

  testWidgets('Switching tabs closes the keyboard', (tester) async {
    await _pump(tester);
    await focusField(tester, 'tab ${RouteNames.trainer}');
    final box = tester.getRect(find.byType(FitNavBar));
    await tester.tapAt(Offset(16 + (box.width - 32) * 2.5 / 5, box.top + 35));
    await tester.pumpAndSettle();
    expect(find.text('tab ${RouteNames.trainerWorkouts}'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('Opening and closing a page closes the keyboard', (tester) async {
    await _pump(tester);
    await focusField(tester, 'tab ${RouteNames.trainer}');
    await tester.tap(find.text('open ${RouteNames.clients}'));
    await tester.pumpAndSettle();
    expect(find.text('clients'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);

    await focusField(tester, 'clients');
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    expect(find.text('tab ${RouteNames.trainer}'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('Tapping empty space closes the keyboard, tapping the field keeps it', (tester) async {
    await _pump(tester);
    await focusField(tester, 'tab ${RouteNames.trainer}');
    await tester.tap(find.byKey(ValueKey('field-tab ${RouteNames.trainer}')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tapAt(const Offset(200, 500));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
