import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trainhub/app.dart';
import 'package:trainhub/core/config/env_config.dart';
import 'package:trainhub/core/constants/app_constants.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/features/home/presentation/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EnvConfig.init();
    await setupDependencyInjection();
  });

  testWidgets('App boots splash then navigates home', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );
    await tester.pump();

    expect(find.textContaining('TrainHub'), findsWidgets);

    await tester.pump(AppConstants.splashDuration);
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
  });
}
