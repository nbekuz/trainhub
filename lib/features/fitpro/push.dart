import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:trainhub/core/logger/app_logger.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';

/// Asks for notification permission on the home screen and registers the device token.
class PushRegistration {
  PushRegistration._();

  static bool _started = false;

  static Future<void> askOnHome() async {
    if (_started) return;
    _started = true;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      final status = settings.authorizationStatus;
      final allowed = status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;
      if (!allowed) return;

      final token = await messaging.getToken();
      await _send(token);
      messaging.onTokenRefresh.listen(_send);
    } catch (error, stack) {
      AppLogger.e('Push registration failed', error, stack);
    }
  }

  static Future<void> _send(String? token) async {
    if (token == null || token.length < 8) return;
    try {
      await FitApi.registerDevice(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
        deviceName: Platform.isIOS ? 'iOS' : 'Android',
        appVersion: '1.0.0',
      );
    } catch (error, stack) {
      AppLogger.e('Device token was not saved', error, stack);
    }
  }
}
