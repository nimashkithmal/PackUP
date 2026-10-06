import "package:firebase_core/firebase_core.dart" show FirebaseOptions;
import "package:flutter/foundation.dart" show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError("Add Firebase options for this platform.");
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "REPLACE_ME",
    appId: "REPLACE_ME",
    messagingSenderId: "REPLACE_ME",
    projectId: "REPLACE_ME",
    storageBucket: "REPLACE_ME.appspot.com",
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: "REPLACE_ME",
    appId: "REPLACE_ME",
    messagingSenderId: "REPLACE_ME",
    projectId: "REPLACE_ME",
    storageBucket: "REPLACE_ME.appspot.com",
    iosBundleId: "com.packup.app",
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "REPLACE_ME",
    appId: "REPLACE_ME",
    messagingSenderId: "REPLACE_ME",
    projectId: "REPLACE_ME",
    storageBucket: "REPLACE_ME.appspot.com",
  );
}
