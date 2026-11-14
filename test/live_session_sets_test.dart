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

/// In-memory backend for one live session.
class _FakeBackend {
  _FakeBackend({this.previous = const []});

  final List<Map<String, dynamic>> previous;
  final requests = <RequestOptions>[];
  final exercises = <Map<String, dynamic>>[];
  var _setSeq = 100;

  Map<String, dynamic> get session => {
        'id': 77,
        'status': 'in_progress',
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'clients': const [],
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
          {'id': 3, 'name': 'Ягодичный мост', 'primary_muscle': 'glutes'},
        ],
      };
    }
    if (o.method == 'GET' && path.startsWith('/sessions/77/previous/')) return previous;
    if (o.method == 'POST' && path == '/sessions/77/exercises') {
      exercises.add({'id': 5, 'exercise_id': body['exercise_id'], 'name': 'Ягодичный мост', 'rest_sec': 90, 'sets': []});
      return session;
    }
    final addSet = RegExp(r'^/sessions/77/exercises/(\d+)/sets$').firstMatch(path);
    if (o.method == 'POST' && addSet != null) {
      final ex = exercises.firstWhere((e) => '${e['id']}' == addSet.group(1));
      final sets = ex['sets'] as List;
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
    return null;
  }

  List<Map<String, dynamic>> bodies(String method, Pattern path) => [
        for (final r in requests)
          if (r.method == method && path.allMatches(r.path).isNotEmpty) Map<String, dynamic>.from(r.data as Map),
      ];
}

Future<_FakeBackend> _pump(WidgetTester tester, {List<Map<String, dynamic>> previous = const []}) async {
  SharedPreferences.setMockInitialValues({StorageKeys.authToken: 'token'});
  await getIt.reset();
  await setupDependencyInjection();
  final backend = _FakeBackend(previous: previous);
  getIt<ApiClient>().dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': backend.handle(o)})),
        ),
      );
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const LiveSessionPage(sessionId: 77))]);
  await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
  return backend;
}

Future<void> _addExercise(WidgetTester tester) async {
  await tester.tap(find.text('+ Добавить упражнения'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ягодичный мост'));
  await tester.pumpAndSettle();
}

/// The "+" of the stepper showing [value]; [index] picks among equal values (top to bottom).
Finder _plusOf(String value, {int index = 0}) => find.descendant(
      of: find.ancestor(of: find.text(value).at(index), matching: find.byType(Row)).first,
      matching: find.byIcon(Icons.add),
    );

Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('A new exercise starts with one set taken from the previous workout', (tester) async {
    final backend = await _pump(tester, previous: [
      {'set_index': 1, 'weight_kg': 50, 'reps': 12},
      {'set_index': 2, 'weight_kg': 60, 'reps': 8},
    ]);
    await _addExercise(tester);

    expect(backend.bodies('POST', RegExp(r'/exercises/5/sets$')).map((b) => (b['weight_kg'], b['reps'])), [(60, 8)]);
    expect(find.text('Вес'), findsOneWidget);
    expect(find.text('Повторы'), findsOneWidget);
    // One editable set row plus the «Прошлая тренировка» chip.
    expect(find.text('60 кг'), findsNWidgets(2));
    expect(_plusOf('60 кг'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('Without history the starting set is 40 kg x 10', (tester) async {
    final backend = await _pump(tester);
    await _addExercise(tester);
    expect(backend.bodies('POST', RegExp(r'/exercises/5/sets$')).map((b) => (b['weight_kg'], b['reps'])), [(40, 10)]);
    expect(find.text('40 кг'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('Add set copies the last set, and each set stays editable', (tester) async {
    final backend = await _pump(tester);
    await _addExercise(tester);

    // Edit the starting set: 40 -> 42.5 kg.
    await tester.tap(_plusOf('40 кг'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(backend.bodies('PATCH', '/sessions/77/sets/100').last['weight_kg'], 42.5);

    await tester.tap(find.text('+ Добавить подход'));
    await tester.pumpAndSettle();
    expect(
      backend.bodies('POST', RegExp(r'/exercises/5/sets$')).map((b) => (b['weight_kg'], b['reps'])),
      [(40, 10), (42.5, 10)],
    );
    expect(find.text('42.5 кг'), findsNWidgets(2));
    expect(find.textContaining('Отдых'), findsNothing);

    // Second set's reps: 10 -> 11, first set untouched.
    await tester.tap(_plusOf('10', index: 1));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(backend.bodies('PATCH', '/sessions/77/sets/101').last['reps'], 11);
    expect(backend.bodies('PATCH', '/sessions/77/sets/100').map((b) => b['reps']).toSet(), {10});
    expect(find.text('11'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('An edit made right before leaving the page is still sent', (tester) async {
    final backend = await _pump(tester);
    await _addExercise(tester);
    await tester.pump(const Duration(seconds: 4));

    await tester.tap(_plusOf('10'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    expect(backend.bodies('PATCH', '/sessions/77/sets/100').map((b) => b['reps']), [11]);
  });
}
