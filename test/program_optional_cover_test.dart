import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/network/api_client.dart';
import 'package:trainhub/core/storage/storage_keys.dart';
import 'package:trainhub/features/fitpro/screens/trainer/create_program_page.dart';
import 'package:trainhub/features/fitpro/session.dart';

final _requests = <RequestOptions>[];

Map<String, dynamic> _program({String status = 'draft', List<Map<String, dynamic>> days = const []}) => {
      'id': 9,
      'title': 'Без обложки',
      'status': status,
      'source': 'trainer',
      'cover_url': null,
      'weeks': [
        {'id': 1, 'week_index': 1, 'title': 'Неделя 1'},
      ],
      'days': days,
    };

const _dayWithExercise = {
  'id': 3,
  'week_id': 1,
  'title': 'Комплекс 1',
  'exercises': [
    {'id': 1, 'exercise_id': 4, 'name': 'Присед', 'sets': 3, 'reps_min': 8, 'reps_max': 10},
  ],
};

Object? _stub(RequestOptions o) {
  final p = o.path;
  if (o.method == 'POST' && p == '/programs') return _program();
  if (o.method == 'POST' && p == '/programs/9/weeks') return _program();
  if (o.method == 'GET' && p == '/programs/9') return _program(days: [_dayWithExercise]);
  if (o.method == 'POST' && p == '/programs/9/submit') return _program(status: 'published', days: [_dayWithExercise]);
  throw DioException(requestOptions: o, message: 'not stubbed');
}

Future<void> _pump(WidgetTester tester, {int? programId}) async {
  SharedPreferences.setMockInitialValues({StorageKeys.authToken: 'token'});
  await getIt.reset();
  await setupDependencyInjection();
  _requests.clear();
  getIt<ApiClient>().dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (o, h) {
            _requests.add(o);
            try {
              h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': _stub(o)}));
            } on DioException catch (e) {
              h.reject(e);
            }
          },
        ),
      );
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(fitSessionProvider.notifier).signIn(
        const FitUser(id: 1, name: 'Т', surname: '', email: '', uuid: '1', role: FitRole.trainer),
      );
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, _) => Scaffold(
          body: TextButton(onPressed: () => context.push('/create'), child: const Text('open')),
        ),
      ),
      GoRoute(path: '/create', builder: (_, _) => CreateProgramPage(programId: programId)),
    ],
  );
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

bool _sent(String method, String path) => _requests.any((r) => r.method == method && r.path == path);

void main() {
  testWidgets('A program can be created without a cover', (tester) async {
    await _pump(tester);
    expect(find.text('Обложка *'), findsNothing);
    expect(find.text('Обложка'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Без обложки');
    await tester.pump();
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();

    expect(_sent('POST', '/programs'), isTrue);
    expect(_requests.where((r) => r.path.endsWith('/cover')), isEmpty);
    expect(find.text('Добавьте обложку'), findsNothing);
    expect(find.text('Опубликовать'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('A program without a cover can be published', (tester) async {
    await _pump(tester, programId: 9);
    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();

    expect(_sent('POST', '/programs/9/submit'), isTrue);
    expect(find.text('Программа опубликована'), findsOneWidget);
    expect(find.text('open'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
