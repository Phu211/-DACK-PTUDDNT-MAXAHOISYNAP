import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service để gọi LibreTranslate API
/// LibreTranslate là một công cụ dịch mã nguồn mở
/// Bạn có thể sử dụng public instance hoặc tự host
class LibreTranslateService {
  // Public LibreTranslate instance (có thể thay đổi thành instance riêng)
  static const String _defaultApiUrl = 'https://libretranslate.com';
  
  // Hoặc sử dụng instance khác:
  // static const String _defaultApiUrl = 'http://your-libretranslate-server.com';
  
  final String apiUrl;
  
  LibreTranslateService({String? apiUrl}) : apiUrl = apiUrl ?? _defaultApiUrl;

  /// Dịch một đoạn text từ ngôn ngữ nguồn sang ngôn ngữ đích
  /// 
  /// [text] - Text cần dịch
  /// [source] - Mã ngôn ngữ nguồn (ví dụ: 'vi', 'en')
  /// [target] - Mã ngôn ngữ đích (ví dụ: 'en', 'fr')
  /// 
  /// Trả về text đã được dịch
  Future<String> translate({
    required String text,
    required String source,
    required String target,
  }) async {
    if (text.isEmpty) return text;
    if (source == target) return text;

    try {
      final url = Uri.parse('$apiUrl/translate');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'q': text,
          'source': source,
          'target': target,
          'format': 'text',
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Translation request timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final translatedText = data['translatedText'] as String?;
        
        if (translatedText != null && translatedText.isNotEmpty) {
          return translatedText;
        } else {
          debugPrint('LibreTranslate: Empty translation result');
          return text; // Trả về text gốc nếu không dịch được
        }
      } else {
        debugPrint('LibreTranslate API error: ${response.statusCode} - ${response.body}');
        return text; // Trả về text gốc nếu có lỗi
      }
    } catch (e, stackTrace) {
      debugPrint('LibreTranslate error: $e');
      debugPrint('Stack trace: $stackTrace');
      return text; // Trả về text gốc nếu có exception
    }
  }

  /// Dịch nhiều đoạn text cùng lúc
  /// 
  /// [texts] - List các text cần dịch
  /// [source] - Mã ngôn ngữ nguồn
  /// [target] - Mã ngôn ngữ đích
  /// 
  /// Trả về list các text đã được dịch
  Future<List<String>> translateBatch({
    required List<String> texts,
    required String source,
    required String target,
  }) async {
    if (texts.isEmpty) return [];
    if (source == target) return texts;

    // LibreTranslate có thể hỗ trợ batch translation
    // Nhưng để đơn giản, ta sẽ dịch từng text một
    // Có thể tối ưu sau bằng cách gộp nhiều text thành một request
    final results = <String>[];
    
    for (final text in texts) {
      try {
        final translated = await translate(
          text: text,
          source: source,
          target: target,
        );
        results.add(translated);
      } catch (e) {
        debugPrint('Error translating text: $e');
        results.add(text); // Thêm text gốc nếu lỗi
      }
    }
    
    return results;
  }

  /// Kiểm tra xem API có hoạt động không
  Future<bool> checkApiHealth() async {
    try {
      final url = Uri.parse('$apiUrl/languages');
      final response = await http.get(url).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Timeout');
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('LibreTranslate API health check failed: $e');
      return false;
    }
  }

  /// Lấy danh sách các ngôn ngữ được hỗ trợ
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    try {
      final url = Uri.parse('$apiUrl/languages');
      final response = await http.get(url).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        return data.map((lang) {
          final map = lang as Map<String, dynamic>;
          return {
            'code': map['code'] as String? ?? '',
            'name': map['name'] as String? ?? '',
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('Error fetching supported languages: $e');
    }
    
    // Trả về danh sách mặc định nếu không lấy được
    return [
      {'code': 'en', 'name': 'English'},
      {'code': 'vi', 'name': 'Tiếng Việt'},
      {'code': 'fr', 'name': 'Français'},
      {'code': 'es', 'name': 'Español'},
      {'code': 'de', 'name': 'Deutsch'},
      {'code': 'zh', 'name': '中文'},
      {'code': 'ja', 'name': '日本語'},
      {'code': 'ko', 'name': '한국어'},
    ];
  }
}

