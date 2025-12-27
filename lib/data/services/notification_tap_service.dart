import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Central place to capture notification taps (FCM + local notifications)
/// and expose them to the UI (MainScreen).
class NotificationTapService {
  NotificationTapService._();
  static final NotificationTapService instance = NotificationTapService._();

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  Map<String, dynamic>? _pending;
  bool _initialized = false;

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  Map<String, dynamic>? consumePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  Future<void> init() async {
    if (_initialized) return;

    if (kIsWeb) {
      _initialized = true;
      return;
    }

    try {
      // When user taps a push notification while app in background.
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _setPending(message.data, emit: true);
      });

      // When app was terminated and opened via notification tap.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _setPending(initial.data, emit: false);
      }
    } catch (_) {
      // Desktop platforms may not have firebase_messaging implementation.
    }

    _initialized = true;
  }

  void handleLocalNotificationPayload(Map<String, dynamic> data) {
    _setPending(data, emit: true);
  }

  void _setPending(Map<String, dynamic> data, {required bool emit}) {
    if (data.isEmpty) return;
    _pending = Map<String, dynamic>.from(data);
    if (emit) {
      _controller.add(_pending!);
    }
  }
}
