import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web platform is not configured.');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAqQrFhpGeHHtoQVXq8Jw_q0iA0szLfUB8',
    appId: '1:17267525827:android:581e50b6756fd048fffa76',
    messagingSenderId: '17267525827',
    projectId: 'carcare-bf796',
    storageBucket: 'carcare-bf796.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDm5aUFwxlSiLaeh2xZZ3pQSxUhe6HiXWE',
    appId: '1:17267525827:ios:ea2e846441866f57fffa76',
    messagingSenderId: '17267525827',
    projectId: 'carcare-bf796',
    storageBucket: 'carcare-bf796.firebasestorage.app',
    iosBundleId: 'mn.infosystems.carservice-business',
  );
}
