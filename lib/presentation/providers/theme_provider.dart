import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLoading = true;

  ThemeMode get themeMode => _themeMode;
  bool get isLoading => _isLoading;

  ThemeProvider() {
    // Load saved preference immediately
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_themeModeKey);
      if (savedMode != null) {
        final parsedMode = _parseThemeMode(savedMode);
        _themeMode = parsedMode;
        debugPrint(
          'Theme mode loaded from preferences: ${_themeModeToString(parsedMode)}',
        );
        notifyListeners();
      } else {
        // If no saved preference, use system default
        _themeMode = ThemeMode.system;
        debugPrint('No saved theme mode, using system default');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading theme mode: $e');
      // Default to system mode on error
      _themeMode = ThemeMode.system;
      notifyListeners();
    } finally {
      _isLoading = false;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    debugPrint('Theme mode changed to: ${_themeModeToString(mode)}');
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, _themeModeToString(mode));
      debugPrint('Theme mode saved: ${_themeModeToString(mode)}');
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  ThemeMode _parseThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  // Helper methods for UI
  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      // Check system brightness
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  String get currentModeString {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'off';
      case ThemeMode.dark:
        return 'on';
      case ThemeMode.system:
        return 'auto';
    }
  }
}
