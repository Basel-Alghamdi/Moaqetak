// This file contains placeholder Firebase options. Replace values with your
// project configuration or run `flutterfire configure` to generate it.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        return web;
    }
  }

  /// Returns FirebaseOptions for the current platform if they look configured.
  /// If values still contain placeholders, returns null to signal "not set".
  static FirebaseOptions? get maybeCurrentPlatform {
    final opts = kIsWeb
        ? web
        : (() {
            switch (defaultTargetPlatform) {
              case TargetPlatform.android:
                return android;
              case TargetPlatform.iOS:
                return ios;
              case TargetPlatform.macOS:
                return macos;
              case TargetPlatform.windows:
                return windows;
              case TargetPlatform.linux:
                return linux;
              default:
                return web;
            }
          })();
    return _hasRealValues(opts) ? opts : null;
  }

  /// Simple heuristic: if any critical field still starts with
  /// 'REPLACE_WITH_' then the options are not configured.
  static bool _hasRealValues(FirebaseOptions o) {
    bool looksReal(String? v) => v != null && !v.startsWith('REPLACE_WITH_') && v.trim().isNotEmpty;
    // These keys exist across all platforms and are enough to detect placeholders.
    return looksReal(o.apiKey) && looksReal(o.appId) && looksReal(o.projectId);
  }

  // Replace all below values with real values from your Firebase console
  // or run: flutter pub global activate flutterfire_cli && flutterfire configure

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_WITH_WEB_API_KEY',
    appId: 'REPLACE_WITH_WEB_APP_ID',
    messagingSenderId: 'REPLACE_WITH_SENDER_ID',
    projectId: 'REPLACE_WITH_PROJECT_ID',
    authDomain: 'REPLACE_WITH_AUTH_DOMAIN',
    storageBucket: 'REPLACE_WITH_STORAGE_BUCKET',
    measurementId: 'REPLACE_WITH_MEASUREMENT_ID',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_WITH_ANDROID_API_KEY',
    appId: 'REPLACE_WITH_ANDROID_APP_ID',
    messagingSenderId: 'REPLACE_WITH_SENDER_ID',
    projectId: 'REPLACE_WITH_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_STORAGE_BUCKET',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_WITH_IOS_API_KEY',
    appId: 'REPLACE_WITH_IOS_APP_ID',
    messagingSenderId: 'REPLACE_WITH_SENDER_ID',
    projectId: 'REPLACE_WITH_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_STORAGE_BUCKET',
    iosClientId: 'REPLACE_WITH_IOS_CLIENT_ID',
    iosBundleId: 'REPLACE_WITH_IOS_BUNDLE_ID',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'REPLACE_WITH_MACOS_API_KEY',
    appId: 'REPLACE_WITH_MACOS_APP_ID',
    messagingSenderId: 'REPLACE_WITH_SENDER_ID',
    projectId: 'REPLACE_WITH_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_STORAGE_BUCKET',
    iosClientId: 'REPLACE_WITH_MACOS_CLIENT_ID',
    iosBundleId: 'REPLACE_WITH_MACOS_BUNDLE_ID',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'REPLACE_WITH_WINDOWS_API_KEY',
    appId: 'REPLACE_WITH_WINDOWS_APP_ID',
    messagingSenderId: 'REPLACE_WITH_SENDER_ID',
    projectId: 'REPLACE_WITH_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_STORAGE_BUCKET',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'REPLACE_WITH_LINUX_API_KEY',
    appId: 'REPLACE_WITH_LINUX_APP_ID',
    messagingSenderId: 'REPLACE_WITH_SENDER_ID',
    projectId: 'REPLACE_WITH_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_STORAGE_BUCKET',
  );
}
