import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/features/fitpro/auth/auth_pages.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/routes/route_names.dart';

GoRouter _router(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: RouteNames.role, builder: (_, _) => const RolePage()),
        GoRoute(path: RouteNames.login, builder: (_, _) => const LoginPage()),
        GoRoute(path: RouteNames.register, builder: (_, _) => const RegisterPage()),
      ],
    );

Future<ProviderContainer> _pump(WidgetTester tester, String initial) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: _router(initial)),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Login → «Регистрация» asks «Кто вы?» first', (tester) async {
    await _pump(tester, RouteNames.login);
    await tester.tap(find.textContaining('Регистрация'));
    await tester.pumpAndSettle();
    expect(find.text('Кто вы?'), findsOneWidget);
    expect(find.text('Зарегистрироваться'), findsNothing);
  });

  testWidgets('Register without a role redirects to role selection', (tester) async {
    await _pump(tester, RouteNames.register);
    expect(find.text('Кто вы?'), findsOneWidget);
  });

  testWidgets('Chosen role reaches register and is shown', (tester) async {
    final container = await _pump(tester, RouteNames.role);
    await tester.tap(find.text('Тренер'));
    await tester.pump();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(container.read(fitSessionProvider).pendingRole, FitRole.trainer);
    expect(find.text('Вы регистрируетесь как тренер'), findsOneWidget);
  });
}
