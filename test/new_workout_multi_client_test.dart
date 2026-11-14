import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/network/api_client.dart';
import 'package:trainhub/core/storage/storage_keys.dart';
import 'package:trainhub/features/fitpro/screens/trainer/add_calendar_event_page.dart';
import 'package:trainhub/routes/route_names.dart';

final _requests = <RequestOptions>[];
var _eventSeq = 500;

Object? _stub(RequestOptions o) {
  final path = o.path;
  if (o.method == 'GET' && path == '/trainer/clients') {
    return {
      'data': {
        'items': [
          {'id': 11, 'user_id': 101, 'first_name': 'Вадим', 'last_name': 'Фляженков'},
          {'id': 12, 'user_id': 102, 'first_name': 'Вадим', 'last_name': 'Саенко'},
          {'id': 13, 'user_id': 103, 'first_name': 'Иван', 'last_name': 'Петров'},
        ],
      },
    };
  }
  if (o.method == 'POST' && path == '/trainer/calendar') return {'data': {'id': _eventSeq++}};
  if (o.method == 'POST' && path.endsWith('/start-session')) return {'data': {'id': 900}};
  if (o.method == 'POST' && path == '/sessions') return {'data': {'id': 901}};
  return {'data': null};
}

List<Map<String, dynamic>> _bodies(String method, String path) => [
      for (final r in _requests)
        if (r.method == method && r.path == path) Map<String, dynamic>.from(r.data as Map),
    ];

Future<void> _pump(WidgetTester tester, {required bool startNow}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/form'),
              child: const Text('open form'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/form', builder: (_, _) => AddCalendarEventPage(startNow: startNow)),
      GoRoute(path: RouteNames.liveSession, builder: (_, state) => Text('live ${state.extra}')),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('open form'));
  await tester.pumpAndSettle();
}

Future<void> _pickClients(WidgetTester tester, List<String> names) async {
  await tester.tap(find.text('Выберите клиента'));
  await tester.pumpAndSettle();
  for (final name in names) {
    await tester.tap(find.text(name));
    await tester.pump();
  }
  await tester.tap(find.text('Применить (${names.length})'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({StorageKeys.authToken: 'token'});
    await getIt.reset();
    await setupDependencyInjection();
    _requests.clear();
    _eventSeq = 500;
    getIt<ApiClient>().dio.interceptors.insert(
          0,
          InterceptorsWrapper(
            onRequest: (o, handler) {
              _requests.add(o);
              handler.resolve(Response(requestOptions: o, statusCode: 200, data: _stub(o)));
            },
          ),
        );
  });

  testWidgets('Start now with two clients opens one group session', (tester) async {
    await _pump(tester, startNow: true);
    await _pickClients(tester, ['Вадим Фляженков', 'Вадим Саенко']);
    expect(find.text('Вадим Фляженков, Вадим Саенко'), findsOneWidget);

    await tester.tap(find.text('Начать тренировку'));
    await tester.pumpAndSettle();

    final events = _bodies('POST', '/trainer/calendar');
    expect(events.map((e) => e['client_id']), [101]);
    final sessions = _bodies('POST', '/sessions');
    expect(sessions, hasLength(1));
    expect(sessions.single['client_ids'], [101, 102]);
    expect(sessions.single['calendar_event_id'], 500);
    expect(_requests.where((r) => r.path.endsWith('/start-session')), isEmpty);
    expect(find.text('live 901'), findsOneWidget);
  });

  testWidgets('Start now with one client still starts from the calendar event', (tester) async {
    await _pump(tester, startNow: true);
    await _pickClients(tester, ['Вадим Саенко']);
    await tester.tap(find.text('Начать тренировку'));
    await tester.pumpAndSettle();

    expect(_bodies('POST', '/trainer/calendar').map((e) => e['client_id']), [102]);
    expect(_requests.where((r) => r.path == '/trainer/calendar/500/start-session'), hasLength(1));
    expect(_bodies('POST', '/sessions'), isEmpty);
    expect(find.text('live 900'), findsOneWidget);
  });

  testWidgets('Scheduling for three clients creates an event for each', (tester) async {
    await _pump(tester, startNow: false);
    await _pickClients(tester, ['Вадим Фляженков', 'Вадим Саенко', 'Иван Петров']);
    expect(find.text('Вадим Фляженков, Вадим Саенко, +1'), findsOneWidget);

    await tester.tap(find.text('Запланировать тренировку').last);
    await tester.pumpAndSettle();

    final events = _bodies('POST', '/trainer/calendar');
    expect(events.map((e) => e['client_id']), [101, 102, 103]);
    expect(events.map((e) => e['starts_at']).toSet(), hasLength(1));
    expect(find.text('open form'), findsOneWidget);
    expect(find.textContaining('(клиентов: 3)'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('Reset clears the selection in the sheet', (tester) async {
    await _pump(tester, startNow: true);
    await tester.tap(find.text('Выберите клиента'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Иван Петров'));
    await tester.pump();
    expect(find.text('Применить (1)'), findsOneWidget);
    await tester.tap(find.text('Сбросить всё'));
    await tester.pump();
    expect(find.text('Применить'), findsOneWidget);
  });
}
