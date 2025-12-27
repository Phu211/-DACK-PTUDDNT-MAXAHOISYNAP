import 'package:flutter/material.dart';
import '../../data/services/libretranslate_service.dart';
import '../../data/services/translation_cache_service.dart';
import '../../flutter_gen/gen_l10n/app_localizations.dart';

/// Helper để tự động dịch các chuỗi từ AppLocalizations
/// Sử dụng LibreTranslate khi ngôn ngữ không có trong supportedLocales
class TranslationHelper {
  static final LibreTranslateService _translateService = LibreTranslateService();
  static final TranslationCacheService _cacheService = TranslationCacheService();
  
  // Ngôn ngữ mặc định để dịch từ đó (thường là 'vi' hoặc 'en')
  static const String _defaultSourceLanguage = 'vi';
  
  // Danh sách các ngôn ngữ được hỗ trợ sẵn trong AppLocalizations
  static const List<String> _supportedLocales = ['vi', 'en', 'zh'];

  /// Lấy chuỗi đã được dịch
  /// 
  /// [context] - BuildContext để lấy AppLocalizations
  /// [getter] - Function để lấy string từ AppLocalizations
  /// [targetLanguage] - Mã ngôn ngữ đích (nếu null thì lấy từ LanguageProvider)
  /// 
  /// Trả về chuỗi đã được dịch hoặc chuỗi gốc nếu không cần dịch
  static Future<String> getTranslatedString({
    required BuildContext context,
    required String Function(AppLocalizations?) getter,
    String? targetLanguage,
  }) async {
    final localizations = AppLocalizations.of(context);
    final originalText = getter(localizations);
    
    // Lấy target language từ context nếu không được cung cấp
    final target = targetLanguage ?? 
        Localizations.localeOf(context).languageCode;
    
    // Nếu ngôn ngữ đích đã có trong supportedLocales, trả về trực tiếp
    if (_supportedLocales.contains(target)) {
      return originalText;
    }
    
    // Nếu ngôn ngữ đích giống với ngôn ngữ nguồn, không cần dịch
    if (target == _defaultSourceLanguage) {
      return originalText;
    }
    
    // Kiểm tra cache trước
    final cached = await _cacheService.getCachedTranslation(
      text: originalText,
      source: _defaultSourceLanguage,
      target: target,
    );
    
    if (cached != null) {
      return cached;
    }
    
    // Dịch bằng LibreTranslate
    try {
      final translated = await _translateService.translate(
        text: originalText,
        source: _defaultSourceLanguage,
        target: target,
      );
      
      // Lưu vào cache
      await _cacheService.cacheTranslation(
        text: originalText,
        translation: translated,
        source: _defaultSourceLanguage,
        target: target,
      );
      
      return translated;
    } catch (e) {
      // Nếu lỗi, trả về text gốc
      return originalText;
    }
  }

  /// Lấy chuỗi đã được dịch (synchronous version - sử dụng cache)
  /// 
  /// Nếu chưa có trong cache, trả về text gốc và dịch ở background
  static String getTranslatedStringSync({
    required BuildContext context,
    required String Function(AppLocalizations?) getter,
    String? targetLanguage,
  }) {
    final localizations = AppLocalizations.of(context);
    final originalText = getter(localizations);
    
    final target = targetLanguage ?? 
        Localizations.localeOf(context).languageCode;
    
    // Nếu ngôn ngữ đích đã có trong supportedLocales, trả về trực tiếp
    if (_supportedLocales.contains(target)) {
      return originalText;
    }
    
    // Trả về text gốc, dịch sẽ được thực hiện ở background
    // Để tối ưu, có thể implement một cache in-memory
    return originalText;
  }

  /// Dịch một đoạn text tùy ý (không phải từ AppLocalizations)
  /// 
  /// [text] - Text cần dịch
  /// [source] - Mã ngôn ngữ nguồn
  /// [target] - Mã ngôn ngữ đích
  /// 
  /// Trả về text đã được dịch
  static Future<String> translateText({
    required String text,
    required String source,
    required String target,
  }) async {
    if (text.isEmpty) return text;
    if (source == target) return text;
    
    // Kiểm tra cache trước
    final cached = await _cacheService.getCachedTranslation(
      text: text,
      source: source,
      target: target,
    );
    
    if (cached != null) {
      return cached;
    }
    
    // Dịch bằng LibreTranslate
    try {
      final translated = await _translateService.translate(
        text: text,
        source: source,
        target: target,
      );
      
      // Lưu vào cache
      await _cacheService.cacheTranslation(
        text: text,
        translation: translated,
        source: source,
        target: target,
      );
      
      return translated;
    } catch (e) {
      return text; // Trả về text gốc nếu lỗi
    }
  }
}

