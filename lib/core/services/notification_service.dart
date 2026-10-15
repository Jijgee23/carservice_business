import 'dart:convert';
import 'dart:io';

import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/notification_router.dart';
import 'package:carservice_business/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'carservice_default';
  static const _channelName = 'Carservice мэдэгдэл';

  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(_channelId, _channelName, importance: Importance.high),
        );

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // Tap while the app is backgrounded (not terminated).
    FirebaseMessaging.onMessageOpenedApp.listen((m) => NotificationRouter.route(m.data));

    // Tap that cold-started the app from terminated state.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) NotificationRouter.route(initial.data);
  }

  Future<String?> getToken() async {
    if (!kIsWeb && Platform.isIOS) {
      // The APNs token arrives asynchronously after launch, and FCM can't
      // issue a token without it — wait for it instead of giving up at once.
      String? apns;
      for (var i = 0; i < 10 && apns == null; i++) {
        apns = await _messaging.getAPNSToken();
        if (apns == null) await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (apns == null) {
        if (kDebugMode) debugPrint('FCM token: none (no APNs token, simulator?)');
        return 'simulator';
      }
    }
    final token = await _messaging.getToken();
    if (kDebugMode) debugPrint('FCM token: $token');
    return token;
  }

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  void _showForegroundNotification(RemoteMessage message) {
    // Silent, data-only account-closure push (deactivation/deletion,
    // including from the website): never a visible/local notification, so
    // handle it before anything below and return — no `n == null` fallthrough
    // would ever show it anyway (no notification block), but this also keeps
    // it out of `NotificationRouter` and any tap/deep-link path.
    if (message.data['type'] == 'account_closed') {
      Authenticator.onAccountClosed?.call(
        deleted: message.data['reason'] == 'deleted',
      );
      return;
    }
    final n = message.notification;
    if (n == null) return;
    _localNotifications.show(
      id: n.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        NotificationRouter.route(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Ignore malformed payloads — tapping still opens the app.
    }
  }
}
