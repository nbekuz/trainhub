import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/network/api_client.dart';
import 'package:trainhub/core/storage/storage_keys.dart';
import 'package:trainhub/features/fitpro/screens/live_session_page.dart';
import 'package:trainhub/features/fitpro/session.dart';

const _anna = 11;
const _petr = 12;
const _olga = 13;

/// Group session 77 where every exercise belongs to one client.
class _GroupBackend {
  _GroupBackend({this.previousByClient = const {}});

  final Map<int, List<Map<String, dynamic>>> previousByClient;
  final requests = <RequestOptions>[];
  final exercises = <Map<String, dynamic>>[];
  final clients = <Map<String, dynamic>>[
    {'id': _anna, 'first_name': 'Анна', 'last_name': 'Иванова'},
    {'id': _petr, 'first_name': 'Пётр', 'last_name': 'Смирнов'},
  ];
  var _exerciseSeq = 5;
  var _setSeq = 100;

  Map<String, dynamic> get session => {
        'id': 77,
        'status': 'in_progress',
        'lead_client_id': _anna,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'clients': clients,
        'exercises': exercises,
      };

  Object? handle(RequestOptions o) {
    requests.add(o);
    final path = o.path;
    final body = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
    if (o.method == 'GET' && path == '/sessions/77') return session;
    if (o.method == 'GET' && path == '/exercises') {
      return {
        'items': [
          {'id': 3, 'name': 'Жим лёжа', 'primary_muscle': 'chest'},
        ],
      };
    }
    if (o.method == 'GET' && path.startsWith('/sessions/77/previous/')) {
      return previousByClient[int.tryParse('${o.queryParameters['client_id']}')] ?? const [];
    }
    if (o.method == 'POST' && path == '/sessions/77/exercises') {
      exercises.add({
        'id': _exerciseSeq++,
        'exercise_id': body['exercise_id'],
        'name': 'Жим лёжа',
        'client_id': body['client_id'] ?? _anna,
        'sets': [],
      });
      return session;
    }
    final addSet = RegExp(r'^/sessions/77/exercises/(\d+)/sets$').firstMatch(path);
    if (o.method == 'POST' && addSet != null) {
      final sets = exercises.firstWhere((e) => '${e['id']}' == addSet.group(1))['sets'] as List;
      sets.add({
        'id': _setSeq++,
        'set_index': sets.length + 1,
        'weight_kg': body['weight_kg'],
        'reps': body['reps'],
        'completed_at': DateTime.now().toIso8601String(),
      });
      return session;
    }
    final patchSet = RegExp(r'^/sessions/77/sets/(\d+)$').firstMatch(path);
    if (o.method == 'PATCH' && patchSet != null) {
      for (final ex in exercises) {
        for (final s in ex['sets'] as List) {
          if ('${s['id']}' == patchSet.group(1)) s.addAll(body);
        }
      }
      return session;
    }
    if (o.method == 'GET' && path == '/trainer/clients') {
      return {
        'items': [
          {'id': 31, 'user_id': _olga, 'first_name': 'Ольга', 'last_name': 'Петрова'},
        ],
      };
    }
    if (o.method == 'POST' && path == '/sessions/77/clients') {
      clients.add({'id': body['client_id'], 'first_name': 'Ольга', 'last_name': 'Петрова'});
      return session;
    }
    return null;
  }

  List<Map<String, dynamic>> bodies(String method, Pattern path) => [
        for (final r in requests)
          if (r.method == method && path.allMatches(r.path).isNotEmpty) Map<String, dynamic>.from(r.data as Map),
      ];
}

Future<_GroupBackend> _pump(
  WidgetTester tester, {
  Map<int, List<Map<String, dynamic>>> previous = const {},
  void Function(_GroupBackend backend)? setup,
}) async {
  SharedPreferences.setMockInitialValues({StorageKeys.authToken: 'token'});
  await getIt.reset();
  await setupDependencyInjection();
  final backend = _GroupBackend(previousByClient: previous);
  setup?.call(backend);
  getIt<ApiClient>().dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': backend.handle(o)})),
        ),
      );
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(fitSessionProvider.notifier).signIn(
        const FitUser(id: 1, name: 'Тренер', surname: '', email: '', uuid: '1', role: FitRole.trainer),
      );
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const LiveSessionPage(sessionId: 77))]);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
  return backend;
}

Future<void> _addExercise(WidgetTester tester) async {
  await tester.tap(find.text('+ Добавить упражнения'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Жим лёжа').last);
  await tester.pumpAndSettle();
}

/// Waits out toasts that cover the client header, then taps the client.
Future<void> _select(WidgetTester tester, String name) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Finder _plusOf(String value) => find.descendant(
      of: find.ancestor(of: find.text(value).first, matching: find.byType(Row)).first,
      matching: find.byIcon(Icons.add),
    );

Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('Each client has a separate screen with own exercises and weights', (tester) async {
    final backend = await _pump(tester, previous: {
      _petr: [
        {'set_index': 1, 'weight_kg': 100, 'reps': 5},
      ],
    });

    // Anna (lead) is selected first.
    await _addExercise(tester);
    expect(backend.bodies('POST', RegExp(r'/sessions/77/exercises$')).single['client_id'], _anna);
    expect(find.text('40 кг'), findsOneWidget);

    await _select(tester, 'Пётр');
    expect(find.text('40 кг'), findsNothing);
    expect(find.textContaining('Добавьте первое упражнение для Пётр'), findsOneWidget);

    await _addExercise(tester);
    expect(backend.bodies('POST', RegExp(r'/sessions/77/exercises$')).last['client_id'], _petr);
    // Petr's starting set comes from Petr's own previous workout.
    expect(backend.bodies('POST', RegExp(r'/exercises/6/sets$')).single['weight_kg'], 100);
    expect(find.text('100 кг'), findsWidgets);

    await tester.tap(_plusOf('5'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(backend.bodies('PATCH', '/sessions/77/sets/101').last['reps'], 6);

    await _select(tester, 'Анна');
    expect(find.text('40 кг'), findsOneWidget);
    expect(find.text('100 кг'), findsNothing);
    expect(find.text('10'), findsOneWidget);
    expect(backend.bodies('PATCH', '/sessions/77/sets/100'), isEmpty);
    await _finish(tester);
  });

  testWidgets('Each client keeps own active exercise when switching', (tester) async {
    final backend = await _pump(tester);
    await _addExercise(tester);
    await _addExercise(tester);
    expect(backend.exercises.where((e) => e['client_id'] == _anna), hasLength(2));

    await _select(tester, 'Пётр');
    expect(find.text('+ Добавить подход'), findsNothing);

    await _select(tester, 'Анна');
    expect(find.text('+ Добавить подход'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('A newly added client opens on own empty screen', (tester) async {
    final backend = await _pump(tester);
    await _addExercise(tester);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ольга Петрова'));
    await tester.pumpAndSettle();

    expect(backend.bodies('POST', '/sessions/77/clients').single['client_id'], _olga);
    expect(find.textContaining('Добавьте первое упражнение для Ольга'), findsOneWidget);

    await _addExercise(tester);
    expect(backend.bodies('POST', RegExp(r'/sessions/77/exercises$')).last['client_id'], _olga);
    await _finish(tester);
  });

  testWidgets('Clients with the same first name are told apart by the surname initial', (tester) async {
    await _pump(tester, setup: (b) => b.clients[1]['first_name'] = 'Анна');
    expect(find.text('Анна\u00A0И.'), findsOneWidget);
    expect(find.text('Анна\u00A0С.'), findsOneWidget);
    await _select(tester, 'Анна\u00A0С.');
    expect(find.textContaining('Добавьте первое упражнение для Анна\u00A0С.'), findsOneWidget);
    await _finish(tester);
  });
}
