import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/libretranslate_service.dart';

class LanguageProvider extends ChangeNotifier {
  static const String _languageKey = 'app_language';
  static const String _autoTranslateKey = 'auto_translate_enabled';
  static const String _useLibreTranslateKey = 'use_libretranslate';
  
  Locale _locale = const Locale('vi');
  bool _autoTranslate = false;
  bool _useLibreTranslate = true; // Mặc định bật LibreTranslate
  bool _isLoading = true;
  
  final LibreTranslateService _translateService = LibreTranslateService();

  Locale get locale => _locale;
  bool get autoTranslate => _autoTranslate;
  bool get useLibreTranslate => _useLibreTranslate;
  bool get isLoading => _isLoading;

  LanguageProvider() {
    // Load saved preferences immediately
    _loadLanguagePreferences();
  }

  Future<void> _loadLanguagePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load language
      final savedLanguage = prefs.getString(_languageKey);
      if (savedLanguage != null) {
        _locale = Locale(savedLanguage);
        debugPrint('Language loaded from preferences: ${_locale.languageCode}');
      } else {
        debugPrint('No saved language, using default: vi');
      }

      // Load auto-translate setting
      final savedAutoTranslate = prefs.getBool(_autoTranslateKey);
      if (savedAutoTranslate != null) {
        _autoTranslate = savedAutoTranslate;
        debugPrint('Auto-translate loaded from preferences: $_autoTranslate');
      }

      // Load LibreTranslate setting
      final savedUseLibreTranslate = prefs.getBool(_useLibreTranslateKey);
      if (savedUseLibreTranslate != null) {
        _useLibreTranslate = savedUseLibreTranslate;
        debugPrint('Use LibreTranslate loaded from preferences: $_useLibreTranslate');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading language preferences: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> setLanguage(Locale locale) async {
    if (_locale == locale) return;

    _locale = locale;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, locale.languageCode);
      debugPrint('Language saved: ${locale.languageCode}');
    } catch (e) {
      debugPrint('Error saving language: $e');
    }
  }

  Future<void> setAutoTranslate(bool value) async {
    if (_autoTranslate == value) return;

    _autoTranslate = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoTranslateKey, value);
      debugPrint('Auto-translate saved: $value');
    } catch (e) {
      debugPrint('Error saving auto-translate: $e');
    }
  }

  String get currentLanguageCode => _locale.languageCode;

  /// Bật/tắt sử dụng LibreTranslate
  Future<void> setUseLibreTranslate(bool value) async {
    if (_useLibreTranslate == value) return;

    _useLibreTranslate = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_useLibreTranslateKey, value);
      debugPrint('Use LibreTranslate saved: $value');
    } catch (e) {
      debugPrint('Error saving use LibreTranslate: $e');
    }
  }

  /// Kiểm tra xem ngôn ngữ hiện tại có cần dịch không
  /// (tức là không có trong supportedLocales của AppLocalizations)
  bool get needsTranslation {
    const supportedLocales = ['vi', 'en', 'zh'];
    return !supportedLocales.contains(_locale.languageCode);
  }
}
