import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static const String _languageKey = 'app_language';
  static const String _autoTranslateKey = 'auto_translate_enabled';

  /// Get saved language code
  Future<String> getLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_languageKey) ?? 'vi';
    } catch (e) {
      return 'vi';
    }
  }

  /// Save language code
  Future<void> setLanguage(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, languageCode);
    } catch (e) {
      debugPrint('Error saving language: $e');
    }
  }

  /// Check if auto-translate is enabled
  Future<bool> isAutoTranslateEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_autoTranslateKey) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Enable/disable auto-translate
  Future<void> setAutoTranslate(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoTranslateKey, enabled);
    } catch (e) {
      debugPrint('Error saving auto-translate setting: $e');
    }
  }

  /// Get supported languages
  static List<Map<String, String>> getSupportedLanguages() {
    return [
      {
        'code': 'vi',
        'name': 'Tiếng Việt',
        'native': 'Tiếng Việt',
        'flag': '🇻🇳',
      },
      {
        'code': 'en',
        'name': 'English',
        'native': 'English',
        'flag': '🇺🇸',
      },
      {
        'code': 'zh',
        'name': '中文',
        'native': '中文',
        'flag': '🇨🇳',
      },
      {
        'code': 'ja',
        'name': '日本語',
        'native': '日本語',
        'flag': '🇯🇵',
      },
      {
        'code': 'ko',
        'name': '한국어',
        'native': '한국어',
        'flag': '🇰🇷',
      },
      {
        'code': 'th',
        'name': 'ไทย',
        'native': 'ไทย',
        'flag': '🇹🇭',
      },
      {
        'code': 'fr',
        'name': 'Français',
        'native': 'Français',
        'flag': '🇫🇷',
      },
      {
        'code': 'es',
        'name': 'Español',
        'native': 'Español',
        'flag': '🇪🇸',
      },
    ];
  }
}

