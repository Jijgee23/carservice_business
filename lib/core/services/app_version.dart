import 'package:package_info_plus/package_info_plus.dart';

/// The installed build's version, as shown to staff: "1.2.0 (14)" — read
/// from the build (pubspec `version`), so it never drifts from the store.
/// Null when the platform can't say (tests).
Future<String?> appVersionLabel() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty
        ? info.version
        : '${info.version} (${info.buildNumber})';
  } catch (_) {
    return null;
  }
}
