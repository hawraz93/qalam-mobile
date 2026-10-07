import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';

/// What a push notification points at.
class PushTarget {
  PushTarget(this.category, this.entityId);

  final String category;
  final int? entityId;

  static PushTarget? fromData(Map<String, dynamic> data) {
    final category = data['category']?.toString();
    if (category == null || category.isEmpty) return null;
    return PushTarget(category, int.tryParse(data['entity_id']?.toString() ?? ''));
  }
}

class Push {
  static bool _ready = false;
  static String? deviceToken;

  /// Fires when a push arrives while the app is open (refresh badges / lists).
  static final StreamController<RemoteMessage> foreground = StreamController.broadcast();

  /// Fires when the user taps a notification.
  static final StreamController<PushTarget> opened = StreamController.broadcast();

  /// Safe to call without Firebase configured: the app then works without push.
  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (e) {
      debugPrint('Firebase is not configured, push disabled: $e');
      return;
    }

    FirebaseMessaging.onMessage.listen(foreground.add);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
    FirebaseMessaging.instance.onTokenRefresh.listen(_sendToken);
  }

  /// The notification that launched the app from a terminated state, if any.
  static Future<PushTarget?> initialTarget() async {
    if (!_ready) return null;
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null ? null : PushTarget.fromData(message.data);
  }

  /// Asks for permission and registers this phone for the signed-in user.
  static Future<void> registerDevice() async {
    if (!_ready) return;

    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _sendToken(token);
      }
    } catch (e) {
      debugPrint('Could not register for push: $e');
    }
  }

  static Future<void> _sendToken(String token) async {
    deviceToken = token;
    if (!api.isSignedIn) return;

    try {
      await api.post('/devices', {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'device_name': Platform.operatingSystem,
      });
    } catch (e) {
      debugPrint('Could not send device token: $e');
    }
  }

  static void _handleOpen(RemoteMessage message) {
    final target = PushTarget.fromData(message.data);
    if (target != null) opened.add(target);
  }
}
