import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/core/network/api_client.dart';
import 'package:trainhub/core/storage/storage_keys.dart';
import 'package:trainhub/features/fitpro/screens/workout_history_page.dart';

final _requests = <RequestOptions>[];

Map<String, dynamic> _ex(int id, String name, int clientId) => {
      'id': id,
      'exercise_id': id,
      'name': name,
      'client_id': clientId,
      'sets': [
        {'id': id * 10, 'set_index': 1, 'weight_kg': 50, 'reps': 10},
      ],
    };

final _groupSession = {
  'id': 9,
  'status': 'completed',
  'duration_sec': 1800,
  'sets_count': 2,
  'clients': [
    {'id': 11, 'first_name': 'Анна', 'last_name': 'Иванова'},
    {'id': 12, 'first_name': 'Пётр', 'last_name': 'Смирнов'},
  ],
  'exercises': [_ex(1, 'Присед', 11), _ex(2, 'Жим лёжа', 12)],
};

Future<void> _pump(WidgetTester tester, SessionDetailPage page) async {
  SharedPreferences.setMockInitialValues({StorageKeys.authToken: 'token'});
  await getIt.reset();
  await setupDependencyInjection();
  _requests.clear();
  getIt<ApiClient>().dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (o, h) {
            _requests.add(o);
            h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': _groupSession}));
          },
        ),
      );
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('A group workout lists exercises under each client', (tester) async {
    await _pump(tester, const SessionDetailPage(sessionId: 9));
    expect(find.text('Анна Иванова'), findsOneWidget);
    expect(find.text('Пётр Смирнов'), findsOneWidget);
    expect(find.text('Присед'), findsOneWidget);
    expect(find.text('Жим лёжа'), findsOneWidget);
    final anna = tester.getTopLeft(find.text('Анна Иванова')).dy;
    final squat = tester.getTopLeft(find.text('Присед')).dy;
    final petr = tester.getTopLeft(find.text('Пётр Смирнов')).dy;
    final bench = tester.getTopLeft(find.text('Жим лёжа')).dy;
    expect(anna < squat && squat < petr && petr < bench, isTrue);
  });

  testWidgets("From a client's profile only that client's part is shown", (tester) async {
    await _pump(tester, const SessionDetailPage(sessionId: 9, clientId: 12));
    expect(_requests.single.path, '/sessions/9');
    expect(_requests.single.queryParameters, {'client_id': 12});
    expect(find.text('Жим лёжа'), findsOneWidget);
    expect(find.text('Присед'), findsNothing);
    expect(find.text('Пётр Смирнов'), findsNothing);
  });
}
