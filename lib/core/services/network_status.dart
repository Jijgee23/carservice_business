import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the device is on a network, read locally (no request), so an
/// action can skip a call that would only hang while offline. A network
/// without internet still reads as online: callers keep a timeout for that.
abstract class NetworkStatus {
  Future<bool> isOnline();

  /// The online state on every change of network.
  Stream<bool> get changes;
}

/// [NetworkStatus] from the OS (`connectivity_plus`). Without the plugin
/// (tests, unsupported platforms) it reads as online, so callers fall back
/// to simply trying the request.
class DeviceNetworkStatus implements NetworkStatus {
  DeviceNetworkStatus._();
  static final instance = DeviceNetworkStatus._();

  final _connectivity = Connectivity();

  static bool _online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async {
    try {
      return _online(await _connectivity.checkConnectivity());
    } catch (_) {
      return true;
    }
  }

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_online).distinct();
}
