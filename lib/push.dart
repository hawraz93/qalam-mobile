import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';

/// Why a push might not reach this phone, in the order the user should fix them.
enum PushProblem {
  /// Everything looks fine.
  none,

  /// No Google services / Firebase could not hand out a token: push is impossible here.
  unavailable,

  /// Notifications are turned off for the app (permission denied or the alerts channel blocked).
  blocked,

  /// Notifications show but the alerts channel is set to silent.
  silent,

  /// The phone itself is muted: silent/vibrate mode, notification volume at zero or Do Not Disturb.
  phoneMuted,

  /// The phone may kill the app in the background, so pushes stop once the app is closed.
  battery,
}

class PushHealth {
  const PushHealth(this.problem, {this.manufacturer = ''});

  final PushProblem problem;
  final String manufacturer;

  /// Vendors with their own "autostart" page on top of Android's battery optimisation.
  bool get hasAutostartPage {
    final m = manufacturer.toLowerCase();
    return const ['xiaomi', 'redmi', 'poco', 'huawei', 'honor', 'oppo', 'realme', 'vivo', 'iqoo', 'oneplus', 'asus', 'hmd', 'nokia']
        .any(m.contains);
  }
}

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
  static bool _tokenFailed = false;
  static bool _permissionDenied = false;
  static String? deviceToken;

  /// Talks to MainActivity.kt (Android only).
  static const _device = MethodChannel('qalam/device');

  /// "Xiaomi Redmi Note 12 (Android 14)", shown in the admin device list.
  static String _deviceLabel = Platform.operatingSystem;

  /// Same id as the server sends in the FCM payload (android.notification.channel_id)
  static const _channel = AndroidNotificationChannel(
    'qalam_alerts',
    'Al-Qalam alerts',
    description: 'New tickets, complaints, messages and replies',
    importance: Importance.high,
  );

  static final _local = FlutterLocalNotificationsPlugin();

  /// Brand colour for the notification icon and header (same as res/values/colors.xml).
  static const _accent = Color(0xFF910051);

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

    // While the app is closed, Android shows FCM notifications by itself. While it is
    // open, nothing is shown unless the app does it, so foreground messages go through
    // flutter_local_notifications on the same channel.
    await _local.initialize(
      const InitializationSettings(
        // Monochrome pen nib (res/drawable/ic_stat_qalam.xml): Android only draws the
        // alpha channel of a small icon, so the colour logo came out as a white blank.
        android: AndroidInitializationSettings('@drawable/ic_stat_qalam'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final target = PushTarget.fromData(Map<String, dynamic>.from(jsonDecode(payload) as Map));
        if (target != null) opened.add(target);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // iOS: show banners while the app is in the foreground too
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
    FirebaseMessaging.instance.onTokenRefresh.listen(_sendToken);

    final status = await _status();
    if (status != null) {
      _deviceLabel = '${status['manufacturer']} ${status['model']} (Android ${status['androidVersion']})';
    }
  }

  static Future<Map<String, dynamic>?> _status() async {
    if (!Platform.isAndroid) return null;
    try {
      final status = await _device.invokeMapMethod<String, dynamic>('status');
      return status;
    } catch (e) {
      debugPrint('Device status unavailable: $e');
      return null;
    }
  }

  /// Checks the phone-side reasons a push would not show or make a sound.
  static Future<PushHealth> health() async {
    if (!_ready || _tokenFailed) return const PushHealth(PushProblem.unavailable);
    if (!Platform.isAndroid) return const PushHealth(PushProblem.none);

    final status = await _status();
    if (status == null) return const PushHealth(PushProblem.none);

    final manufacturer = status['manufacturer']?.toString() ?? '';
    final channelImportance = status['channelImportance'] as int?;

    // 0 = IMPORTANCE_NONE: the user blocked the channel itself
    if (_permissionDenied || status['notificationsEnabled'] == false || channelImportance == 0) {
      return PushHealth(PushProblem.blocked, manufacturer: manufacturer);
    }
    if (status['channelSound'] == false) {
      return PushHealth(PushProblem.silent, manufacturer: manufacturer);
    }
    // ringerMode 2 = normal; dndFilter 1 = Do Not Disturb off
    if ((status['ringerMode'] as int? ?? 2) != 2 ||
        (status['notificationVolume'] as int? ?? 1) == 0 ||
        (status['dndFilter'] as int? ?? 1) != 1) {
      return PushHealth(PushProblem.phoneMuted, manufacturer: manufacturer);
    }
    if (status['batteryOptimized'] == true) {
      return PushHealth(PushProblem.battery, manufacturer: manufacturer);
    }
    return PushHealth(PushProblem.none, manufacturer: manufacturer);
  }

  static Future<void> openNotificationSettings({bool channel = false}) async {
    try {
      await _device.invokeMethod('openNotificationSettings', {'channel': channel});
    } catch (e) {
      debugPrint('Could not open notification settings: $e');
    }
  }

  static Future<void> allowBackground() async {
    try {
      await _device.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('Could not open battery settings: $e');
    }
  }

  static Future<void> openAutostartSettings() async {
    try {
      await _device.invokeMethod('openAutostartSettings');
    } catch (e) {
      debugPrint('Could not open autostart settings: $e');
    }
  }

  static Future<void> openSoundSettings() async {
    try {
      await _device.invokeMethod('openSoundSettings');
    } catch (e) {
      debugPrint('Could not open sound settings: $e');
    }
  }

  /// Everything the phone reports, for the "notification check" dialog.
  static Future<Map<String, dynamic>> rawStatus() async {
    final status = await _status() ?? <String, dynamic>{};
    return {
      'firebase': _ready,
      'token': deviceToken == null ? null : '${deviceToken!.substring(0, 12)}…',
      'tokenFailed': _tokenFailed,
      'permissionDenied': _permissionDenied,
      ...status,
    };
  }

  /// Shows a notification on the alerts channel without the server, to test sound on this phone.
  static Future<void> showTest(String title, String body) async {
    if (!_ready || !Platform.isAndroid) return;
    await _local.show(
      0,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@drawable/ic_stat_qalam',
          color: _accent,
        ),
      ),
    );
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
      final settings = await FirebaseMessaging.instance.requestPermission();
      _permissionDenied = settings.authorizationStatus == AuthorizationStatus.denied;

      // Throws or returns null on phones without Google services (Huawei 2019+, some imports)
      final token = await FirebaseMessaging.instance.getToken();
      _tokenFailed = token == null;
      if (token != null) {
        await _sendToken(token);
      }
    } catch (e) {
      _tokenFailed = true;
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
        'device_name': _deviceLabel,
      });
    } catch (e) {
      debugPrint('Could not send device token: $e');
    }
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    foreground.add(message);

    final notification = message.notification;
    if (notification == null || !Platform.isAndroid) return;

    await _local.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@drawable/ic_stat_qalam',
          color: _accent,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static void _handleOpen(RemoteMessage message) {
    final target = PushTarget.fromData(message.data);
    if (target != null) opened.add(target);
  }
}
