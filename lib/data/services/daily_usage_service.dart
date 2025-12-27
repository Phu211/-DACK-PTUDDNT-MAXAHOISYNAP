import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ghi lại thời gian sử dụng ứng dụng theo từng ngày (trên mỗi thiết bị).
///
/// - Dùng WidgetsBindingObserver để lắng nghe lifecycle (resumed/paused).
/// - Mỗi lần app hoạt động (resumed) sẽ bắt đầu session, khi paused/inactive thì
///   cộng dồn vào tổng thời gian của ngày hiện tại.
class DailyUsageService with WidgetsBindingObserver {
  DailyUsageService._();
  static final DailyUsageService instance = DailyUsageService._();

  static const String _storageKey = 'daily_usage_seconds';

  bool _initialized = false;
  DateTime? _sessionStart;
  final Map<String, int> _usageSeconds = {}; // key: yyyy-MM-dd, value: seconds

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((key, value) {
            final seconds = int.tryParse(value.toString());
            if (seconds != null) {
              _usageSeconds[key] = seconds;
            }
          });
        }
      }
      WidgetsBinding.instance.addObserver(this);
      _initialized = true;
    } catch (e) {
      debugPrint('DailyUsageService init error: $e');
    }
  }

  Future<void> disposeService() async {
    WidgetsBinding.instance.removeObserver(this);
    await _endSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startSession();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _endSession();
        break;
    }
  }

  void _startSession() {
    _sessionStart ??= DateTime.now();
  }

  Future<void> _endSession() async {
    if (_sessionStart == null) return;
    final end = DateTime.now();
    final diff = end.difference(_sessionStart!).inSeconds;
    _sessionStart = null;

    if (diff <= 0) return;

    final key = _dateKey(end);
    _usageSeconds[key] = (_usageSeconds[key] ?? 0) + diff;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_usageSeconds));
    } catch (e) {
      debugPrint('DailyUsageService save error: $e');
    }
  }

  String _dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  /// Thời gian sử dụng hôm nay.
  Future<Duration> getTodayUsage() async {
    if (!_initialized) await init();
    final now = DateTime.now();
    final key = _dateKey(now);
    final seconds = _usageSeconds[key] ?? 0;
    return Duration(seconds: seconds);
  }

  /// Lấy lịch sử sử dụng trong [days] ngày gần nhất (bao gồm hôm nay).
  /// Map có key là chuỗi yyyy-MM-dd.
  Future<Map<String, Duration>> getUsageForLastDays(int days) async {
    if (!_initialized) await init();
    final result = <String, Duration>{};
    final now = DateTime.now();

    for (int i = 0; i < days; i++) {
      final day = now.subtract(Duration(days: i));
      final key = _dateKey(day);
      final seconds = _usageSeconds[key] ?? 0;
      if (seconds > 0) {
        result[key] = Duration(seconds: seconds);
      }
    }
    return result;
  }
}
