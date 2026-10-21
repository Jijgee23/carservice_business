import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/features/orders/presentation/screens/order_payment_screen.dart';

void main() {
  test(
    'QR decoder accepts data URIs and rejects malformed or empty values',
    () {
      expect(decodeQrImage(null), isNull);
      expect(decodeQrImage(''), isNull);
      expect(decodeQrImage('not-base64'), isNull);
      expect(decodeQrImage('data:image/png;base64,SGVsbG8='), isA<Uint8List>());
      expect(decodeQrImage('SGVsbG8='), isA<Uint8List>());
    },
  );

  test('bank URL validation allows HTTPS/custom schemes only', () {
    expect(isSafeBankUrl('https://bank.example/pay?id=1'), isTrue);
    for (final scheme in qpayBankSchemes) {
      expect(isSafeBankUrl('$scheme://pay?id=1'), isTrue, reason: scheme);
    }
    // A bank app QPay added later is kept as long as the link carries the
    // invoice QR.
    expect(isSafeBankUrl('newbank://q?qPay_QRcode=0002010102'), isTrue);
    for (final value in [
      'javascript:alert(1)',
      'data:text/html,hello',
      'file:///etc/passwd',
      'about:blank',
      'blob:https://example.test/id',
      'http://bank.example/pay',
      'evil://bank.example/pay',
      '/missing-scheme',
      'http://bank.example/q?qPay_QRcode=1',
      'intent://q?qPay_QRcode=1',
      'javascript://q?qPay_QRcode=1',
    ]) {
      expect(isSafeBankUrl(value), isFalse, reason: value);
    }
  });

  test('every QPay bank scheme is declared for Android and iOS', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    for (final scheme in qpayBankSchemes) {
      expect(
        manifest,
        contains('android:scheme="$scheme"'),
        reason: 'AndroidManifest <queries>: $scheme',
      );
      expect(
        plist,
        contains('<string>$scheme</string>'),
        reason: 'Info.plist LSApplicationQueriesSchemes: $scheme',
      );
    }
  });
}
