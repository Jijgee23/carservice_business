import 'dart:io';
import 'dart:math' as math;

import 'package:carservice_business/core/network/api_client.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/notification_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class DeviceService {
  DeviceService._();
  static final DeviceService instance = DeviceService._();

  static const _boxName = 'device';
  static const _idKey = 'device_id';

  Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  String get _deviceId {
    final box = Hive.box(_boxName);
    var id = box.get(_idKey) as String?;
    if (id == null) {
      final rng = math.Random();
      final bytes = List.generate(16, (_) => rng.nextInt(256));
      id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      box.put(_idKey, id);
    }
    return id;
  }

  String get _platform {
    if (kIsWeb) return 'WEB';
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isIOS) return 'IOS';
    return 'WEB';
  }

  /// `auth/login` / `auth/activate`-ийн body-д нэмэх төхөөрөмжийн талбарууд —
  /// сервер нэвтрэлтийн үед push төхөөрөмжийг өөрөө бүртгэж, `auth/logout`
  /// үед устгадаг тул тусдаа `POST /devices` / `DELETE /devices/{id}`
  /// дуудах шаардлагагүй. `deviceId` нь token солигдоход ашигладаг ижил
  /// install id (нэг утас = нэг Device мөр).
  ///
  /// Хэзээ ч throw хийхгүй: авч чадаагүй талбар (FCM-гүй, тестийн орчин г.м.)
  /// орхигдож, сервер 400 + `fieldErrors`-оор хариулна.
  Future<Map<String, Object>> loginFields() async {
    final fields = <String, Object>{};
    try {
      fields['deviceId'] = _deviceId;
    } catch (_) {}
    if (!kIsWeb) {
      if (Platform.isIOS) fields['type'] = 'ios';
      if (Platform.isAndroid) fields['type'] = 'android';
    }
    try {
      final token = await NotificationService.instance.getToken();
      if (token != null && token.isNotEmpty) fields['fcm'] = token;
    } catch (e) {
      debugPrint('DeviceService.loginFields fcm error: $e');
    }
    try {
      final info = DeviceInfoPlugin();
      if (!kIsWeb && Platform.isAndroid) {
        final a = await info.androidInfo;
        fields['model'] = '${a.manufacturer} ${a.model}'.trim();
        fields['os'] = 'Android ${a.version.release}';
      } else if (!kIsWeb && Platform.isIOS) {
        final i = await info.iosInfo;
        fields['model'] = i.modelName;
        fields['os'] = '${i.systemName} ${i.systemVersion}';
      }
    } catch (e) {
      debugPrint('DeviceService.loginFields device info error: $e');
    }
    return fields;
  }

  /// App эхлэхэд (нэвтэрсэн хэрэглэгчтэй) дуудна — FCM token-ийг шинэчилнэ.
  Future<void> registerAfterLogin() async {
    final token = await NotificationService.instance.getToken();
    await _register(token);
  }

  /// FCM token шинэчлэгдэхэд дуудна.
  Future<void> updateToken(String fcmToken) async {
    if (Authenticator.user == null) return;
    await _register(fcmToken);
  }

  Future<void> _register(String? fcmToken) async {
    try {
      await api(
        Api.post,
        'devices',
        body: {'deviceId': _deviceId, 'platform': _platform, 'firebaseToken': ?fcmToken},
      );
    } catch (e) {
      debugPrint('DeviceService.registerAfterLogin error: $e');
    }
  }
}
