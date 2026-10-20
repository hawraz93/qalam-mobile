import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crash reports to Firebase Crashlytics, so the IT team learns about a crash on
/// someone's phone without them having to report it.
///
/// Only release builds send anything; debug runs and the screenshot tests stay local.
/// Reports carry the account id (never the name, email or phone) to tell people apart.
class CrashReports {
  static bool _on = false;

  /// After Firebase.initializeApp (Push.init). Does nothing when Firebase is not configured.
  static Future<void> init() async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

      // Errors inside Flutter (layout, build, …)
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      // Everything else that escapes (async code, plugins)
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      _on = true;
    } catch (e) {
      debugPrint('Crashlytics unavailable: $e');
    }
  }

  /// Ties reports to the signed-in account (by id only); cleared on sign-out.
  static void setUser(Map<String, dynamic>? user) {
    if (!_on) return;
    FirebaseCrashlytics.instance.setUserIdentifier(user?['id']?.toString() ?? '');
  }

  /// A handled problem worth knowing about (not a crash).
  static void record(Object error, StackTrace stack, {String? reason}) {
    if (!_on) return;
    FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
  }
}
