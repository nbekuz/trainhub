import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/network/api_client.dart';
import 'package:trainhub/core/storage/storage_keys.dart';
import 'package:trainhub/features/fitpro/screens/trainer/edit_program_day_page.dart';

final _requests = <RequestOptions>[];
final _dayExercises = <Map<String, dynamic>>[];

Object? _stub(RequestOptions o) {
  if (o.method == 'GET' && o.path == '/dictionaries') return const [];
  if (o.method == 'GET' && o.path == '/exercises') {
    return {
      'items': [
        {'id': 4, 'name': 'Присед', 'primary_muscle': 'quads'},
      ],
    };
  }
  if (o.method == 'POST' && o.path == '/programs/1/days/2/exercises') {
    final body = Map<String, dynamic>.from(o.data as Map);
    _dayExercises.add({'id': 70, 'name': 'Присед', ...body});
    return {
      'id': 1,
      'days': [
        {'id': 2, 'title': 'День 1', 'exercises': _dayExercises},
      ],
    };
  }
  return null;
}

void main() {
  testWidgets('A picked exercise is added right away, without the sets/reps window', (tester) async {
    SharedPreferences.setMockInitialValues({StorageKeys.authToken: 'token'});
    await getIt.reset();
    await setupDependencyInjection();
    getIt<ApiClient>().dio.interceptors.insert(
          0,
          InterceptorsWrapper(
            onRequest: (o, h) {
              _requests.add(o);
              h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': _stub(o)}));
            },
          ),
        );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: EditProgramDayPage(programId: 1, day: {'id': 2, 'title': 'День 1', 'exercises': []}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Нет упражнений'), findsOneWidget);

    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Присед'));
    await tester.pumpAndSettle();

    expect(find.text('Подходы'), findsNothing);
    expect(find.text('Повторения от'), findsNothing);
    final posts = _requests.where((r) => r.method == 'POST').toList();
    expect(posts.single.data, {'exercise_id': 4});
    expect(find.text('Присед'), findsOneWidget);
    expect(find.text('Нет упражнений'), findsNothing);
    expect(find.textContaining('подход'), findsNothing);
  });
}
