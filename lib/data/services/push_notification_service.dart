import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'notification_tap_service.dart';
import 'settings_service.dart';

/// Hiển thị thông báo hệ thống (Android/iOS) để người dùng thấy "ngoài app".
///
/// Lưu ý:
/// - Android: notification payload từ FCM sẽ tự hiện khi app background/terminated.
///   Khi app foreground, ta tự show local notification.
/// - iOS: cần request permission; background data-only cần cấu hình thêm.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const String _channelId = 'synap_general';
  static const String _channelName = 'Synap';
  static const String _channelDesc = 'Thông báo tin nhắn & hoạt động';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _backgroundInitialized = false;

  /// Initialize local notification plugin.
  ///
  /// - [forBackground]: when called from FCM background isolate, skip permission
  ///   requests and skip registering foreground listeners.
  Future<void> init({bool forBackground = false}) async {
    // ✅ Cho phép init lại khi forBackground=true để đảm bảo notification channel được tạo
    // trong background handler (vì background handler chạy trong isolate riêng)
    if (forBackground) {
      if (_backgroundInitialized) return;
    } else {
      if (_initialized) return;
    }
    
    if (kIsWeb) {
      if (forBackground) {
        _backgroundInitialized = true;
      } else {
        _initialized = true;
      }
      return;
    }

    if (!forBackground) {
      // Request runtime permission on Android 13+
      if (Platform.isAndroid) {
        try {
          final status = await Permission.notification.status;
          if (!status.isGranted) {
            final result = await Permission.notification.request();
            debugPrint('Notification permission request result: $result');
          }
        } catch (e) {
          debugPrint('Error requesting notification permission: $e');
        }
      }
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const windowsInit = WindowsInitializationSettings(
      appName: 'Synap',
      appUserModelId: 'com.synap.dack',
      guid: 'b138aa7f-0db9-4da4-9f41-4e7e5d2ce3e1',
    );

    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      windows: Platform.isWindows ? windowsInit : null,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse resp) {
        // Xử lý notification action buttons (accept/reject)
        if (resp.actionId != null && resp.actionId!.isNotEmpty) {
          final payload = resp.payload;
          if (payload != null && payload.isNotEmpty) {
            try {
              final decoded = jsonDecode(payload);
              if (decoded is Map) {
                final data = Map<String, dynamic>.from(decoded);
                // Thêm action vào data để MainScreen có thể xử lý
                data['actionId'] = resp.actionId;
                NotificationTapService.instance.handleLocalNotificationPayload(data);
              }
            } catch (_) {}
          }
          return;
        }
        
        // Xử lý notification tap thông thường
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            NotificationTapService.instance.handleLocalNotificationPayload(
              Map<String, dynamic>.from(decoded),
            );
          }
        } catch (_) {}
      },
    );

    // Android channels
    if (Platform.isAndroid) {
      final android = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        // General notifications channel
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );

        // Calls channel với priority cao nhất
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            'synap_calls',
            'Cuộc gọi',
            description: 'Thông báo cuộc gọi đến',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            showBadge: true,
          ),
        );
      }
    }

    if (!forBackground) {
      // Foreground FCM -> show local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        // Tránh đè luồng cuộc gọi (đã xử lý riêng ở CallNotificationService)
        if (message.data['type'] == 'incoming_call') return;

        await showFromRemoteMessage(message);
      });
      _initialized = true;
    } else {
      _backgroundInitialized = true;
    }
  }

  /// Show call notification với priority cao và sound
  Future<void> showCallNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    if (kIsWeb) return;

    // Android: High priority notification với sound và vibration
    final androidDetails = AndroidNotificationDetails(
      'synap_calls', // Sử dụng channel riêng cho calls
      'Cuộc gọi',
      channelDescription: 'Thông báo cuộc gọi đến',
      importance: Importance.max, // Highest priority
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 250, 500]),
      sound: const RawResourceAndroidNotificationSound('ringtone'),
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true, // Hiển thị full screen khi có cuộc gọi
      ongoing: true, // Notification không thể swipe away
      autoCancel: false, // Không tự động đóng
      actions: const [
        AndroidNotificationAction(
          'accept',
          'Trả lời',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'reject',
          'Từ chối',
          showsUserInterface: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'ringtone.caf',
      interruptionLevel: InterruptionLevel.critical,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _local.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: jsonEncode(data),
    );
  }

  /// Chỉ show local notification khi app đang mở (foreground).
  /// Background/terminated: nên gửi FCM kèm notification payload để Android tự hiện.
  Future<void> showFromRemoteMessage(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    final title =
        notification?.title ??
        (data['title']?.toString().isNotEmpty == true
            ? data['title'].toString()
            : 'Synap');

    final body =
        notification?.body ??
        (data['body']?.toString().isNotEmpty == true
            ? data['body'].toString()
            : 'Bạn có thông báo mới');

    // Kiểm tra setting tắt âm thanh thông báo
    final isSoundMuted = await SettingsService.isNotificationSoundMuted();

    // Android details
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: !isSoundMuted,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: !isSoundMuted,
    );

    const windowsDetails = WindowsNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      windows: windowsDetails,
    );

    // Use stable id to avoid spam: fallback to hash.
    final id = message.messageId?.hashCode ?? DateTime.now().millisecond;

    await _local.show(
      id,
      title,
      body,
      details,
      payload: data.isEmpty ? null : jsonEncode(data),
    );
  }

  /// Hiển thị local notification đơn giản (không kèm payload).
  Future<void> showSimpleNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;

    // Kiểm tra setting tắt âm thanh thông báo
    final isSoundMuted = await SettingsService.isNotificationSoundMuted();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: !isSoundMuted,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: !isSoundMuted,
    );

    const windowsDetails = WindowsNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      windows: windowsDetails,
    );

    await _local.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
    );
  }
}
