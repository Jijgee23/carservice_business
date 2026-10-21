import 'dart:async';

import 'package:carservice_business/core/services/pending_logout_store.dart';
import 'package:carservice_business/app/app.dart';
import 'package:carservice_business/core/keys/keys.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/device_service.dart';
import 'package:carservice_business/core/services/notification_service.dart';
import 'package:carservice_business/core/services/saved_login_store.dart';
import 'package:carservice_business/core/services/legal_consent_store.dart';
import 'package:carservice_business/firebase_options.dart';
import 'package:carservice_business/core/widgets/screens/error_screens.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  runGuardian();
  runZonedGuarded(() async {
    flutterRequired();
    try {
      await appIniter();
    } catch (e, s) {
      // Config, storage or Firebase failed: the app can't run, but must
      // not sit on the splash screen either.
      onException(e, s);
      runApp(const StartupFailedApp());
      return;
    }
    onTokenRefresh();
    // A restored session never goes through login, so re-register here —
    // otherwise the server keeps a stale token (e.g. from an old Firebase app).
    if (Authenticator.user != null) unawaited(DeviceService.instance.registerAfterLogin());
    runApp(CarserviceApp());
  }, onException);
}

void runGuardian() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  // Debug: the full screen with the exception. Release: a small notice that
  // fits the failed widget's slot.
  ErrorWidget.builder = (details) =>
      kDebugMode ? AppErrorScreen(details: details) : const AppErrorBox();
}

Future appIniter() async {
  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Hive.initFlutter();
  await initializeDateFormatting('mn');
  await Authenticator.init();
  // Last signed-in identifier, prefilled on the login page.
  await HiveSavedLoginStore.init();
  // Sign-outs made offline, sent to the server once back online.
  await HivePendingLogoutStore.init();
  // Who accepted the terms, checked by the router after login.
  await LegalConsentStore.init();
  await DeviceService.instance.init();
  await NotificationService.instance.init();
}

void onTokenRefresh() {
  NotificationService.instance.onTokenRefresh.listen(DeviceService.instance.updateToken);
}

void flutterRequired() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
}

void onException(Object e, StackTrace s) {
  if (!kDebugMode) return;
  debugPrint("ERROR=======> \n${e.toString()}");
  debugPrint("STACKTRACE=======> \n${s.toString()}");
}
