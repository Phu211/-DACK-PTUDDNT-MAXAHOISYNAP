import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service để cache các bản dịch đã dịch từ LibreTranslate
/// Giúp tránh gọi API nhiều lần cho cùng một text
class TranslationCacheService {
  static const String _cachePrefix = 'translation_cache_';
  static const int _maxCacheSize = 1000; // Giới hạn số lượng cache
  static const Duration _cacheExpiry = Duration(days: 30); // Cache hết hạn sau 30 ngày

  /// Lấy bản dịch từ cache
  /// 
  /// [text] - Text gốc
  /// [source] - Mã ngôn ngữ nguồn
  /// [target] - Mã ngôn ngữ đích
  /// 
  /// Trả về bản dịch nếu có trong cache, null nếu không có
  Future<String?> getCachedTranslation({
    required String text,
    required String source,
    required String target,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(text, source, target);
      final cachedData = prefs.getString(cacheKey);
      
      if (cachedData != null) {
        final data = jsonDecode(cachedData) as Map<String, dynamic>;
        final cachedTime = DateTime.parse(data['timestamp'] as String);
        final translatedText = data['translation'] as String;
        
        // Kiểm tra xem cache còn hạn không
        if (DateTime.now().difference(cachedTime) < _cacheExpiry) {
          return translatedText;
        } else {
          // Xóa cache đã hết hạn
          await prefs.remove(cacheKey);
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('Error getting cached translation: $e');
      return null;
    }
  }

  /// Lưu bản dịch vào cache
  /// 
  /// [text] - Text gốc
  /// [translation] - Bản dịch
  /// [source] - Mã ngôn ngữ nguồn
  /// [target] - Mã ngôn ngữ đích
  Future<void> cacheTranslation({
    required String text,
    required String translation,
    required String source,
    required String target,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(text, source, target);
      
      final data = {
        'translation': translation,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      await prefs.setString(cacheKey, jsonEncode(data));
      
      // Giới hạn kích thước cache
      await _limitCacheSize(prefs);
    } catch (e) {
      debugPrint('Error caching translation: $e');
    }
  }

  /// Xóa tất cả cache
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_cachePrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('Error clearing translation cache: $e');
    }
  }

  /// Tạo cache key từ text, source và target
  String _getCacheKey(String text, String source, String target) {
    final hash = text.hashCode.toString();
    return '$_cachePrefix${source}_${target}_$hash';
  }

  /// Giới hạn kích thước cache bằng cách xóa các cache cũ nhất
  Future<void> _limitCacheSize(SharedPreferences prefs) async {
    try {
      final keys = prefs.getKeys().where((k) => k.startsWith(_cachePrefix)).toList();
      
      if (keys.length > _maxCacheSize) {
        // Sắp xếp theo timestamp và xóa các cache cũ nhất
        final cacheEntries = <MapEntry<String, DateTime>>[];
        
        for (final key in keys) {
          final cachedData = prefs.getString(key);
          if (cachedData != null) {
            try {
              final data = jsonDecode(cachedData) as Map<String, dynamic>;
              final timestamp = DateTime.parse(data['timestamp'] as String);
              cacheEntries.add(MapEntry(key, timestamp));
            } catch (e) {
              // Nếu không parse được, xóa luôn
              await prefs.remove(key);
            }
          }
        }
        
        // Sắp xếp theo timestamp (cũ nhất trước)
        cacheEntries.sort((a, b) => a.value.compareTo(b.value));
        
        // Xóa các cache cũ nhất
        final toRemove = cacheEntries.length - _maxCacheSize;
        for (int i = 0; i < toRemove; i++) {
          await prefs.remove(cacheEntries[i].key);
        }
      }
    } catch (e) {
      debugPrint('Error limiting cache size: $e');
    }
  }
}

