import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_notification_service.dart';

/// Đơn giản nhắc người dùng nghỉ giải lao sau một khoảng thời gian dùng app.
///
/// - Lưu trạng thái vào SharedPreferences (theo thiết bị).
/// - Khi được bật, sẽ gửi local notification định kỳ (foreground/background).
class BreakReminderService {
  BreakReminderService._();
  static final BreakReminderService instance = BreakReminderService._();

  static const String _enabledKey = 'break_reminder_enabled';
  static const String _intervalKey = 'break_reminder_interval_minutes';

  bool _initialized = false;
  bool _enabled = false;
  int _intervalMinutes = 60;
  Timer? _timer;

  bool get enabled => _enabled;
  int get intervalMinutes => _intervalMinutes;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await init();
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? false;
      _intervalMinutes = prefs.getInt(_intervalKey) ?? 60;

      if (_enabled) {
        _startTimer();
      }

      _initialized = true;
    } catch (e) {
      debugPrint('BreakReminderService init error: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e) {
      debugPrint('BreakReminderService setEnabled error: $e');
    }
    _restartTimer();
  }

  Future<void> setIntervalMinutes(int minutes) async {
    if (minutes <= 0) return;
    _intervalMinutes = minutes;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_intervalKey, minutes);
    } catch (e) {
      debugPrint('BreakReminderService setIntervalMinutes error: $e');
    }
    if (_enabled) {
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_enabled) {
      _startTimer();
    }
  }

  void _startTimer() {
    if (_intervalMinutes <= 0) return;
    _timer = Timer.periodic(
      Duration(minutes: _intervalMinutes),
      (_) async {
        await _showReminder();
      },
    );
  }

  Future<void> _showReminder() async {
    try {
      await PushNotificationService.instance.showSimpleNotification(
        title: 'Đã đến lúc nghỉ ngơi',
        body: 'Hãy rời màn hình vài phút để thư giãn mắt và cơ thể.',
      );
    } catch (e) {
      debugPrint('BreakReminderService showReminder error: $e');
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}


