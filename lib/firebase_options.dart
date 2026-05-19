

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;











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
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBYzoq6keok1RbzgvqE6_iFGCmCmWBNzLo',
    appId: '1:526952035891:web:d8e2ebf3c3f693bf5f9546',
    messagingSenderId: '526952035891',
    projectId: 'flutter-chat-app-3e625',
    authDomain: 'flutter-chat-app-3e625.firebaseapp.com',
    databaseURL: 'https://flutter-chat-app-3e625-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'flutter-chat-app-3e625.firebasestorage.app',
    measurementId: 'G-KQYS9ZMPE8',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA3Y0n-Jdjxym66sjvNJ3pptxRrMMJGUps',
    appId: '1:526952035891:android:9b4692acbd398e085f9546',
    messagingSenderId: '526952035891',
    projectId: 'flutter-chat-app-3e625',
    databaseURL: 'https://flutter-chat-app-3e625-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'flutter-chat-app-3e625.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD0HZbNu6ZSwUHJneBDGeMjwlH8tpbXMdY',
    appId: '1:526952035891:ios:1a28e0c8c68df9b35f9546',
    messagingSenderId: '526952035891',
    projectId: 'flutter-chat-app-3e625',
    databaseURL: 'https://flutter-chat-app-3e625-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'flutter-chat-app-3e625.firebasestorage.app',
    androidClientId: '526952035891-96rt2s9b0unekvjoa4ocq807gati4efe.apps.googleusercontent.com',
    iosClientId: '526952035891-bk2qe5tjelm5uj1b7f0acf5f9k5h1hh1.apps.googleusercontent.com',
    iosBundleId: 'com.duytq.flutterchatdemo',
  );
}
