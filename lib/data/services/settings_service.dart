import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _autoplayKey = 'settings_autoplay_videos';
  static const String _muteSoundKey = 'settings_mute_notification_sound';
  static const String _dataSaverKey = 'settings_data_saver';
  static const String _activityStatusKey = 'settings_show_activity_status';
  static const String _readReceiptsKey = 'settings_read_receipts';
  static const String _suggestFriendsKey = 'settings_suggest_friends';
  static const String _suggestContentKey = 'settings_suggest_content';

  /// Kiểm tra xem có bật tự động phát video không
  static Future<bool> isAutoplayVideosEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_autoplayKey) ?? true; // Mặc định là true
    } catch (_) {
      return true;
    }
  }

  /// Kiểm tra xem có tắt âm thanh thông báo không
  static Future<bool> isNotificationSoundMuted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_muteSoundKey) ?? false; // Mặc định là false (có âm thanh)
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra xem có bật chế độ tiết kiệm dữ liệu không
  static Future<bool> isDataSaverEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_dataSaverKey) ?? false; // Mặc định là false
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra xem có hiển thị trạng thái hoạt động không
  static Future<bool> isActivityStatusEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_activityStatusKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Kiểm tra xem có bật read receipts không
  static Future<bool> isReadReceiptsEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_readReceiptsKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Kiểm tra xem có bật gợi ý kết bạn không
  static Future<bool> isSuggestFriendsEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_suggestFriendsKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Kiểm tra xem có bật gợi ý nội dung không
  static Future<bool> isSuggestContentEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_suggestContentKey) ?? true;
    } catch (_) {
      return true;
    }
  }
}

