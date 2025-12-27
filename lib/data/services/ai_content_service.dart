import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';

/// AI Content Assistant Service
/// Hỗ trợ: caption, hashtag, dịch, phân tích cảm xúc
/// Hỗ trợ nhiều providers: Groq (miễn phí), OpenRouter, Gemini, OpenAI
class AIContentService {
  static String get _provider => AppConstants.aiProvider;
  static String get _apiKey => AppConstants.aiApiKey;

  // Base URLs cho các providers
  static String get _baseUrl {
    switch (_provider) {
      case 'groq':
        return 'https://api.groq.com/openai/v1';
      case 'openrouter':
        return 'https://openrouter.ai/api/v1';
      case 'gemini':
        return 'https://generativelanguage.googleapis.com/v1beta';
      case 'openai':
      default:
        return 'https://api.openai.com/v1';
    }
  }

  // Models cho mỗi provider
  static String get _model {
    switch (_provider) {
      case 'groq':
        return 'llama-3.1-8b-instant'; // Hoặc 'mixtral-8x7b-32768'
      case 'openrouter':
        return 'deepseek/deepseek-chat'; // Free model
      case 'gemini':
        return 'gemini-1.5-flash';
      case 'openai':
      default:
        return 'gpt-3.5-turbo';
    }
  }

  // Headers cho mỗi provider
  Map<String, String> get _headers {
    final headers = <String, String>{'Content-Type': 'application/json'};

    switch (_provider) {
      case 'openrouter':
        headers['Authorization'] = 'Bearer $_apiKey';
        headers['HTTP-Referer'] = 'https://github.com/your-repo'; // Optional
        headers['X-Title'] = 'Synap App'; // Optional
        break;
      case 'groq':
      case 'openai':
        headers['Authorization'] = 'Bearer $_apiKey';
        break;
      case 'gemini':
        // Gemini dùng query parameter thay vì header
        break;
      default:
        headers['Authorization'] = 'Bearer $_apiKey';
    }

    return headers;
  }

  /// Generate AI suggestions for text content
  /// Returns: caption, hashtags, translation, sentiment analysis
  Future<AIContentSuggestions?> generateSuggestions({
    required String text,
    String? imageUrl,
    String? targetLanguage,
  }) async {
    try {
      if (text.trim().isEmpty && imageUrl == null) {
        if (kDebugMode) {
          print('AI Service: No text and no image, returning null');
        }
        return null;
      }

      // Nếu không có API key, trả về suggestions mẫu (demo)
      if (_apiKey.isEmpty || _apiKey == 'YOUR_API_KEY') {
        if (kDebugMode) {
          print('AI Service: No API key, using mock suggestions');
        }
        return _generateMockSuggestions(text, imageUrl);
      }

      // Build request body tùy theo provider
      final requestBody = _buildRequestBody(text, imageUrl, targetLanguage);

      // Build URL (Gemini dùng query parameter)
      Uri requestUrl;
      if (_provider == 'gemini') {
        requestUrl = Uri.parse('$_baseUrl/models/$_model:generateContent?key=$_apiKey');
      } else {
        requestUrl = Uri.parse('$_baseUrl/chat/completions');
      }

      // Gọi AI API
      if (kDebugMode) {
        print('AI Service: Calling API - Provider: $_provider, URL: $requestUrl');
        print('AI Service: Request body keys: ${requestBody.keys}');
      }

      final response = await http.post(requestUrl, headers: _headers, body: jsonEncode(requestBody));

      if (kDebugMode) {
        print('AI Service: Response status: ${response.statusCode}');
        if (response.statusCode != 200) {
          print('AI Service: Error response: ${response.body}');
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content;

        // Parse response tùy theo provider
        if (_provider == 'gemini') {
          content = data['candidates'][0]['content']['parts'][0]['text'] as String;
        } else {
          // Groq, OpenRouter, OpenAI
          if (data['choices'] != null && data['choices'].isNotEmpty) {
            content = data['choices'][0]['message']['content'] as String;
          } else {
            if (kDebugMode) {
              print('AI Service: No choices in response: ${data.keys}');
            }
            return _generateMockSuggestions(text, imageUrl);
          }
        }

        if (kDebugMode) {
          print('AI Service: Raw content: ${content.substring(0, content.length > 200 ? 200 : content.length)}...');
        }

        final suggestions = _parseAIResponse(content, text);

        if (kDebugMode) {
          print(
            'AI Service: Parsed suggestions - Caption: ${suggestions.caption.substring(0, suggestions.caption.length > 50 ? 50 : suggestions.caption.length)}...',
          );
          print('AI Service: Hashtags: ${suggestions.hashtags.length}');
        }

        return suggestions;
      } else {
        if (kDebugMode) {
          print('AI API Error: ${response.statusCode} - ${response.body}');
        }
        // Fallback to mock suggestions
        return _generateMockSuggestions(text, imageUrl);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error generating AI suggestions: $e');
        print('Stack trace: $stackTrace');
      }
      // Fallback to mock suggestions
      return _generateMockSuggestions(text, imageUrl);
    }
  }

  /// Chat with AI - allows user to request custom content generation
  /// Returns AI response as text
  Future<String?> chatWithAI({
    required String userMessage,
    String? contextText,
    String? imageUrl,
    List<Map<String, String>>? conversationHistory,
  }) async {
    try {
      // Nếu không có API key, trả về response mẫu
      if (_apiKey.isEmpty || _apiKey == 'YOUR_API_KEY') {
        if (kDebugMode) {
          print('AI Service: No API key, using mock chat response');
        }
        return 'Tôi hiểu bạn muốn: $userMessage. Vui lòng cấu hình API key để sử dụng tính năng chat với AI.';
      }

      // Build messages array với conversation history
      final messages = <Map<String, dynamic>>[];
      
      // System message
      String systemMessage = 'Bạn là trợ lý AI chuyên giúp tạo nội dung cho mạng xã hội. Bạn có thể giúp viết lại caption, đề xuất hashtags, dịch nội dung, và các yêu cầu khác liên quan đến bài đăng.';
      
      if (contextText != null && contextText.isNotEmpty) {
        systemMessage += '\n\nNội dung bài viết hiện tại: "$contextText"';
      }
      
      if (imageUrl != null && imageUrl.isNotEmpty) {
        systemMessage += '\n\nCó kèm theo hình ảnh.';
      }
      
      messages.add({
        'role': 'system',
        'content': systemMessage,
      });

      // Add conversation history if provided
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        for (final msg in conversationHistory) {
          messages.add({
            'role': msg['role'] ?? 'user',
            'content': msg['content'] ?? '',
          });
        }
      }

      // Add current user message
      messages.add({
        'role': 'user',
        'content': userMessage,
      });

      // Build request body
      Map<String, dynamic> requestBody;
      Uri requestUrl;

      if (_provider == 'gemini') {
        // Gemini format
        final parts = <Map<String, dynamic>>[];
        for (final msg in messages) {
          if (msg['role'] == 'system') {
            parts.add({'text': '${msg['content']}\n\nUser: '});
          } else if (msg['role'] == 'user') {
            parts.add({'text': '${msg['content']}\n\n'});
          } else if (msg['role'] == 'assistant') {
            parts.add({'text': 'Assistant: ${msg['content']}\n\n'});
          }
        }
        
        requestBody = {
          'contents': [
            {
              'parts': parts,
            },
          ],
          'generationConfig': {
            'maxOutputTokens': 1000,
            'temperature': 0.7,
          },
        };
        requestUrl = Uri.parse('$_baseUrl/models/$_model:generateContent?key=$_apiKey');
      } else {
        // OpenAI/Groq/OpenRouter format
        requestBody = {
          'model': _model,
          'messages': messages,
          'max_tokens': 1000,
          'temperature': 0.7,
        };
        requestUrl = Uri.parse('$_baseUrl/chat/completions');
      }

      if (kDebugMode) {
        print('AI Service: Chat request - Provider: $_provider');
        print('AI Service: User message: $userMessage');
      }

      final response = await http.post(requestUrl, headers: _headers, body: jsonEncode(requestBody));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content;

        if (_provider == 'gemini') {
          content = data['candidates'][0]['content']['parts'][0]['text'] as String;
        } else {
          if (data['choices'] != null && data['choices'].isNotEmpty) {
            content = data['choices'][0]['message']['content'] as String;
          } else {
            if (kDebugMode) {
              print('AI Service: No choices in chat response');
            }
            return 'Xin lỗi, tôi không thể phản hồi lúc này. Vui lòng thử lại.';
          }
        }

        if (kDebugMode) {
          print('AI Service: Chat response: ${content.substring(0, content.length > 200 ? 200 : content.length)}...');
        }

        return content;
      } else {
        if (kDebugMode) {
          print('AI Chat Error: ${response.statusCode} - ${response.body}');
        }
        return 'Xin lỗi, đã xảy ra lỗi khi kết nối với AI. Vui lòng thử lại sau.';
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error in chatWithAI: $e');
        print('Stack trace: $stackTrace');
      }
      return 'Xin lỗi, đã xảy ra lỗi: ${e.toString()}';
    }
  }

  /// Generate caption from image
  Future<String?> generateImageCaption(String imageUrl) async {
    try {
      // Nếu không có API key, trả về caption mẫu
      if (_apiKey.isEmpty || _apiKey == 'YOUR_API_KEY') {
        return 'Một bức ảnh đẹp';
      }

      // Vision API chỉ hỗ trợ một số providers
      if (_provider != 'openai' && _provider != 'gemini') {
        // Groq và OpenRouter không hỗ trợ vision tốt, dùng text description
        return null;
      }

      // Gọi Vision API
      final requestBody = _buildVisionRequestBody(imageUrl);
      Uri requestUrl;

      if (_provider == 'gemini') {
        requestUrl = Uri.parse('$_baseUrl/models/gemini-1.5-flash:generateContent?key=$_apiKey');
      } else {
        requestUrl = Uri.parse('$_baseUrl/chat/completions');
      }

      final response = await http.post(requestUrl, headers: _headers, body: jsonEncode(requestBody));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (_provider == 'gemini') {
          return data['candidates'][0]['content']['parts'][0]['text'] as String;
        } else {
          return data['choices'][0]['message']['content'] as String;
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error generating image caption: $e');
      }
      return null;
    }
  }

  String _buildPrompt(String text, String? imageUrl, String? targetLanguage) {
    final buffer = StringBuffer();

    if (text.isNotEmpty) {
      buffer.writeln('Nội dung bài viết: "$text"');
    }

    if (imageUrl != null) {
      buffer.writeln('Có kèm theo hình ảnh.');
    }

    buffer.writeln('\nHãy cung cấp:');
    buffer.writeln('1. Caption cải thiện (ngắn gọn, hấp dẫn)');
    buffer.writeln('2. Hashtags phù hợp (5-10 hashtags)');

    if (targetLanguage != null && targetLanguage != 'vi') {
      buffer.writeln('3. Bản dịch sang $targetLanguage');
    }

    buffer.writeln('4. Phân tích cảm xúc (positive/neutral/negative)');
    buffer.writeln('\nTrả về dưới dạng JSON với format:');
    buffer.writeln('{"caption": "...", "hashtags": ["#tag1", "#tag2"], "translation": "...", "sentiment": "positive"}');

    return buffer.toString();
  }

  // Build request body tùy theo provider
  Map<String, dynamic> _buildRequestBody(String text, String? imageUrl, String? targetLanguage) {
    final prompt = _buildPrompt(text, imageUrl, targetLanguage);

    switch (_provider) {
      case 'gemini':
        return {
          'contents': [
            {
              'parts': [
                {
                  'text':
                      'You are a helpful content assistant. Generate suggestions for social media posts including: improved caption, relevant hashtags, translation, and sentiment analysis.\n\n$prompt\n\nTrả về dưới dạng JSON với format:\n{"caption": "...", "hashtags": ["#tag1", "#tag2"], "translation": "...", "sentiment": "positive"}',
                },
              ],
            },
          ],
          'generationConfig': {'maxOutputTokens': 500, 'temperature': 0.7},
        };
      case 'openrouter':
      case 'groq':
      case 'openai':
      default:
        return {
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are a helpful content assistant. Generate suggestions for social media posts including: improved caption, relevant hashtags, translation, and sentiment analysis.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 500,
          'temperature': 0.7,
        };
    }
  }

  // Build vision request body
  Map<String, dynamic> _buildVisionRequestBody(String imageUrl) {
    switch (_provider) {
      case 'gemini':
        return {
          'contents': [
            {
              'parts': [
                {'text': 'Hãy mô tả bức ảnh này một cách ngắn gọn và hấp dẫn cho mạng xã hội.'},
                {
                  'inlineData': {
                    'mimeType': 'image/jpeg',
                    'data': imageUrl, // Cần base64 encode
                  },
                },
              ],
            },
          ],
          'generationConfig': {'maxOutputTokens': 150},
        };
      case 'openai':
      default:
        return {
          'model': 'gpt-4-vision-preview',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'Hãy mô tả bức ảnh này một cách ngắn gọn và hấp dẫn cho mạng xã hội.'},
                {
                  'type': 'image_url',
                  'image_url': {'url': imageUrl},
                },
              ],
            },
          ],
          'max_tokens': 150,
        };
    }
  }

  AIContentSuggestions _parseAIResponse(String content, String originalText) {
    try {
      // Try to find JSON in response (có thể có text kèm theo)
      // Tìm JSON object, có thể nested
      String? jsonString;

      // Method 1: Tìm JSON object đầy đủ (có thể nested)
      final jsonStart = content.indexOf('{');
      if (jsonStart != -1) {
        int braceCount = 0;
        int jsonEnd = jsonStart;
        for (int i = jsonStart; i < content.length; i++) {
          if (content[i] == '{') braceCount++;
          if (content[i] == '}') braceCount--;
          if (braceCount == 0) {
            jsonEnd = i + 1;
            break;
          }
        }
        if (jsonEnd > jsonStart) {
          jsonString = content.substring(jsonStart, jsonEnd);
        }
      }

      // Method 2: Nếu không tìm thấy, thử parse toàn bộ content như JSON
      if (jsonString == null && content.trim().startsWith('{')) {
        jsonString = content.trim();
      }

      if (jsonString != null) {
        if (kDebugMode) {
          print(
            'AI Service: Found JSON: ${jsonString.substring(0, jsonString.length > 200 ? 200 : jsonString.length)}...',
          );
        }

        final json = jsonDecode(jsonString);
        final caption = json['caption'] as String? ?? originalText;
        final hashtags = json['hashtags'] != null
            ? List<String>.from(json['hashtags']).map((h) => h.startsWith('#') ? h : '#$h').toList()
            : <String>[];
        final translation = json['translation'] as String?;
        final sentiment = json['sentiment'] as String? ?? 'neutral';

        return AIContentSuggestions(
          caption: caption,
          hashtags: hashtags,
          translation: translation,
          sentiment: sentiment,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing AI response: $e');
        print('Content: ${content.substring(0, content.length > 500 ? 500 : content.length)}');
      }
    }

    // Fallback: Nếu không parse được JSON, thử extract thông tin từ text
    if (kDebugMode) {
      print('AI Service: Falling back to mock suggestions');
    }
    return _generateMockSuggestions(originalText, null);
  }

  AIContentSuggestions _generateMockSuggestions(String text, String? imageUrl) {
    // Generate mock suggestions for demo
    final hashtags = <String>[];
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    // If we have an image but no text, generate image-based suggestions
    if (hasImage && text.trim().isEmpty) {
      return AIContentSuggestions(
        caption: 'Một khoảnh khắc đẹp được ghi lại 📸',
        hashtags: ['#photo', '#moment', '#life', '#beautiful', '#share', '#vietnam', '#daily', '#memories'],
        translation: null,
        sentiment: 'positive',
      );
    }

    // Extract keywords and generate hashtags
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.length > 3 && !hashtags.contains('#$word')) {
        hashtags.add('#$word');
        if (hashtags.length >= 5) break;
      }
    }

    // Add common hashtags
    if (hashtags.length < 5) {
      hashtags.addAll(['#vietnam', '#life', '#daily', '#share']);
    }

    // Improve caption
    String improvedCaption = text;
    if (text.isEmpty && hasImage) {
      improvedCaption = 'Một khoảnh khắc đẹp được ghi lại 📸';
    } else if (text.length > 100) {
      improvedCaption = '${text.substring(0, 97)}...';
    } else if (text.isNotEmpty) {
      improvedCaption = text;
    }

    // Simple sentiment analysis
    String sentiment = 'neutral';
    final positiveWords = ['vui', 'hạnh phúc', 'tuyệt', 'đẹp', 'tốt', 'thích'];
    final negativeWords = ['buồn', 'không', 'xấu', 'tệ', 'ghét'];

    final lowerText = text.toLowerCase();
    if (positiveWords.any((w) => lowerText.contains(w))) {
      sentiment = 'positive';
    } else if (negativeWords.any((w) => lowerText.contains(w))) {
      sentiment = 'negative';
    } else if (hasImage) {
      sentiment = 'positive'; // Images are usually positive
    }

    return AIContentSuggestions(
      caption: improvedCaption.isNotEmpty ? improvedCaption : 'Một khoảnh khắc đẹp được ghi lại 📸',
      hashtags: hashtags.take(8).toList(),
      translation: null,
      sentiment: sentiment,
    );
  }

  /// Generate smart reply suggestions for comments/messages
  /// Returns list of 3-5 short reply suggestions
  Future<List<String>> generateSmartReplies({
    required String originalText,
    String? contextText,
    bool isReply = false,
  }) async {
    try {
      if (originalText.trim().isEmpty) {
        return [];
      }

      // Nếu không có API key, trả về suggestions mẫu
      if (_apiKey.isEmpty || _apiKey == 'YOUR_API_KEY') {
        return _generateMockSmartReplies(originalText, isReply);
      }

      final prompt = isReply
          ? 'Người dùng đã viết: "$originalText"\n\n${contextText != null ? "Trong ngữ cảnh: $contextText\n\n" : ""}Hãy tạo 3-5 câu trả lời ngắn gọn, tự nhiên và phù hợp (mỗi câu dưới 20 từ). Trả về dưới dạng JSON array: ["reply1", "reply2", "reply3"]'
          : 'Nội dung: "$originalText"\n\n${contextText != null ? "Ngữ cảnh: $contextText\n\n" : ""}Hãy tạo 3-5 câu trả lời ngắn gọn, tự nhiên và phù hợp (mỗi câu dưới 20 từ). Trả về dưới dạng JSON array: ["reply1", "reply2", "reply3"]';

      Map<String, dynamic> requestBody;
      Uri requestUrl;

      if (_provider == 'gemini') {
        requestBody = {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {'maxOutputTokens': 200, 'temperature': 0.8},
        };
        requestUrl = Uri.parse('$_baseUrl/models/$_model:generateContent?key=$_apiKey');
      } else {
        requestBody = {
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content': 'Bạn là trợ lý AI giúp tạo câu trả lời ngắn gọn và tự nhiên cho mạng xã hội.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 200,
          'temperature': 0.8,
        };
        requestUrl = Uri.parse('$_baseUrl/chat/completions');
      }

      final response = await http.post(requestUrl, headers: _headers, body: jsonEncode(requestBody));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content;

        if (_provider == 'gemini') {
          content = data['candidates'][0]['content']['parts'][0]['text'] as String;
        } else {
          if (data['choices'] != null && data['choices'].isNotEmpty) {
            content = data['choices'][0]['message']['content'] as String;
          } else {
            return _generateMockSmartReplies(originalText, isReply);
          }
        }

        // Parse JSON array từ response
        try {
          final jsonStart = content.indexOf('[');
          final jsonEnd = content.lastIndexOf(']') + 1;
          if (jsonStart != -1 && jsonEnd > jsonStart) {
            final jsonString = content.substring(jsonStart, jsonEnd);
            final replies = List<String>.from(jsonDecode(jsonString));
            return replies.take(5).toList();
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing smart replies JSON: $e');
          }
        }

        // Fallback: extract từ text
        final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
        final replies = <String>[];
        for (final line in lines) {
          final clean = line.replaceAll(RegExp(r'^[-•\d.\s"]+|["\s]+$'), '').trim();
          if (clean.isNotEmpty && clean.length < 100) {
            replies.add(clean);
            if (replies.length >= 5) break;
          }
        }
        return replies.isNotEmpty ? replies : _generateMockSmartReplies(originalText, isReply);
      }

      return _generateMockSmartReplies(originalText, isReply);
    } catch (e) {
      if (kDebugMode) {
        print('Error generating smart replies: $e');
      }
      return _generateMockSmartReplies(originalText, isReply);
    }
  }

  List<String> _generateMockSmartReplies(String text, bool isReply) {
    final lowerText = text.toLowerCase();
    if (lowerText.contains('cảm ơn') || lowerText.contains('thanks')) {
      return ['Không có gì!', 'Rất vui được giúp bạn', 'Chúc bạn một ngày tốt lành'];
    } else if (lowerText.contains('đẹp') || lowerText.contains('tuyệt')) {
      return ['Cảm ơn bạn!', 'Bạn quá khen', 'Rất vui bạn thích'];
    } else if (lowerText.contains('?')) {
      return ['Để mình suy nghĩ', 'Câu hỏi hay đấy', 'Mình sẽ tìm hiểu'];
    } else {
      return ['Đồng ý!', 'Hay quá', 'Cảm ơn bạn đã chia sẻ'];
    }
  }

  /// Moderate content - detect spam, toxic, inappropriate content
  /// Returns moderation score (0.0-1.0) where higher = more problematic
  Future<AIContentModeration> moderateContent(String text) async {
    try {
      if (text.trim().isEmpty) {
        return AIContentModeration(score: 0.0, isToxic: false, isSpam: false, reason: null);
      }

      // Nếu không có API key, dùng rule-based fallback
      if (_apiKey.isEmpty || _apiKey == 'YOUR_API_KEY') {
        return _ruleBasedModeration(text);
      }

      final prompt = 'Phân tích nội dung sau và đánh giá mức độ không phù hợp (spam, toxic, inappropriate):\n\n"$text"\n\nTrả về JSON: {"score": 0.0-1.0, "isToxic": true/false, "isSpam": true/false, "reason": "lý do nếu có vấn đề"}';

      Map<String, dynamic> requestBody;
      Uri requestUrl;

      if (_provider == 'gemini') {
        requestBody = {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {'maxOutputTokens': 150, 'temperature': 0.3},
        };
        requestUrl = Uri.parse('$_baseUrl/models/$_model:generateContent?key=$_apiKey');
      } else {
        requestBody = {
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content': 'Bạn là hệ thống kiểm duyệt nội dung. Phân tích và đánh giá mức độ không phù hợp.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 150,
          'temperature': 0.3,
        };
        requestUrl = Uri.parse('$_baseUrl/chat/completions');
      }

      final response = await http.post(requestUrl, headers: _headers, body: jsonEncode(requestBody));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content;

        if (_provider == 'gemini') {
          content = data['candidates'][0]['content']['parts'][0]['text'] as String;
        } else {
          if (data['choices'] != null && data['choices'].isNotEmpty) {
            content = data['choices'][0]['message']['content'] as String;
          } else {
            return _ruleBasedModeration(text);
          }
        }

        // Parse JSON
        try {
          final jsonStart = content.indexOf('{');
          final jsonEnd = content.lastIndexOf('}') + 1;
          if (jsonStart != -1 && jsonEnd > jsonStart) {
            final jsonString = content.substring(jsonStart, jsonEnd);
            final json = jsonDecode(jsonString);
            return AIContentModeration(
              score: (json['score'] as num?)?.toDouble() ?? 0.0,
              isToxic: json['isToxic'] as bool? ?? false,
              isSpam: json['isSpam'] as bool? ?? false,
              reason: json['reason'] as String?,
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing moderation JSON: $e');
          }
        }
      }

      return _ruleBasedModeration(text);
    } catch (e) {
      if (kDebugMode) {
        print('Error moderating content: $e');
      }
      return _ruleBasedModeration(text);
    }
  }

  AIContentModeration _ruleBasedModeration(String text) {
    final lowerText = text.toLowerCase();
    double score = 0.0;
    bool isToxic = false;
    bool isSpam = false;
    String? reason;

    // Toxic words
    final toxicWords = ['địt', 'đụ', 'đéo', 'chết', 'ngu', 'ngu si', 'đồ ngu'];
    if (toxicWords.any((w) => lowerText.contains(w))) {
      score = 0.8;
      isToxic = true;
      reason = 'Chứa ngôn ngữ không phù hợp';
    }

    // Spam patterns
    if (text.length > 500 && text.split(' ').length < 10) {
      score = math.max(score, 0.6);
      isSpam = true;
      reason = 'Có thể là spam';
    }

    // Repeated characters
    if (RegExp(r'(.)\1{10,}').hasMatch(text)) {
      score = math.max(score, 0.7);
      isSpam = true;
      reason = 'Chứa ký tự lặp lại nhiều';
    }

    // URLs spam
    final urlCount = RegExp(r'https?://').allMatches(text).length;
    if (urlCount > 3) {
      score = math.max(score, 0.7);
      isSpam = true;
      reason = 'Chứa quá nhiều liên kết';
    }

    return AIContentModeration(score: score, isToxic: isToxic, isSpam: isSpam, reason: reason);
  }

  /// Generate image tags from image URL
  /// Returns list of tags describing the image
  /// Note: Groq/OpenRouter không hỗ trợ Vision API, sẽ dùng text-based approach
  Future<List<String>> generateImageTags(String imageUrl, {String? imageDescription}) async {
    try {
      if (imageUrl.isEmpty) {
        return [];
      }

      if (_apiKey.isEmpty || _apiKey == 'YOUR_API_KEY') {
        return ['photo', 'image', 'picture'];
      }

      // Nếu có imageDescription và provider không hỗ trợ Vision, dùng text-based
      if (imageDescription != null && imageDescription.isNotEmpty) {
        if (_provider == 'groq' || _provider == 'openrouter') {
          return await _generateTagsFromDescription(imageDescription);
        }
      }

      // Chỉ hỗ trợ Gemini và OpenAI Vision cho direct image analysis
      if (_provider != 'gemini' && _provider != 'openai') {
        // Nếu không có description, trả về empty
        return [];
      }

      final prompt = 'Hãy phân tích hình ảnh này và liệt kê các thẻ (tags) mô tả nội dung, mỗi thẻ là 1 từ hoặc cụm từ ngắn. Trả về dưới dạng JSON array: ["tag1", "tag2", "tag3"]';

      Map<String, dynamic> requestBody;
      Uri requestUrl;

      if (_provider == 'gemini') {
        requestBody = {
          'contents': [
            {
              'parts': [
                {'text': prompt},
                {
                  'inlineData': {
                    'mimeType': 'image/jpeg',
                    'data': imageUrl, // Cần base64
                  },
                },
              ],
            },
          ],
          'generationConfig': {'maxOutputTokens': 200, 'temperature': 0.5},
        };
        requestUrl = Uri.parse('$_baseUrl/models/gemini-1.5-flash:generateContent?key=$_apiKey');
      } else {
        requestBody = {
          'model': 'gpt-4-vision-preview',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {'url': imageUrl},
                },
              ],
            },
          ],
          'max_tokens': 200,
          'temperature': 0.5,
        };
        requestUrl = Uri.parse('$_baseUrl/chat/completions');
      }

      final response = await http.post(requestUrl, headers: _headers, body: jsonEncode(requestBody));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content;

        if (_provider == 'gemini') {
          content = data['candidates'][0]['content']['parts'][0]['text'] as String;
        } else {
          if (data['choices'] != null && data['choices'].isNotEmpty) {
            content = data['choices'][0]['message']['content'] as String;
          } else {
            return [];
          }
        }

        // Parse JSON array
        try {
          final jsonStart = content.indexOf('[');
          final jsonEnd = content.lastIndexOf(']') + 1;
          if (jsonStart != -1 && jsonEnd > jsonStart) {
            final jsonString = content.substring(jsonStart, jsonEnd);
            final tags = List<String>.from(jsonDecode(jsonString));
            return tags.take(10).toList();
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing image tags JSON: $e');
          }
        }
      }

      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Error generating image tags: $e');
      }
      return [];
    }
  }

  /// Generate tags from text description (for Groq/OpenRouter)
  Future<List<String>> _generateTagsFromDescription(String description) async {
    try {
      final prompt = 'Từ mô tả sau, hãy tạo 5-10 tags (keywords) ngắn gọn mô tả nội dung, mỗi tag là 1 từ hoặc cụm từ. Trả về dưới dạng JSON array: ["tag1", "tag2", "tag3"]\n\nMô tả: "$description"';

      Map<String, dynamic> requestBody;
      Uri requestUrl;

      if (_provider == 'gemini') {
        requestBody = {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {'maxOutputTokens': 200, 'temperature': 0.5},
        };
        requestUrl = Uri.parse('$_baseUrl/models/$_model:generateContent?key=$_apiKey');
      } else {
        requestBody = {
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content': 'Bạn là trợ lý AI giúp tạo tags từ mô tả nội dung.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 200,
          'temperature': 0.5,
        };
        requestUrl = Uri.parse('$_baseUrl/chat/completions');
      }

      final response = await http.post(requestUrl, headers: _headers, body: jsonEncode(requestBody));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content;

        if (_provider == 'gemini') {
          content = data['candidates'][0]['content']['parts'][0]['text'] as String;
        } else {
          if (data['choices'] != null && data['choices'].isNotEmpty) {
            content = data['choices'][0]['message']['content'] as String;
          } else {
            return [];
          }
        }

        // Parse JSON array
        try {
          final jsonStart = content.indexOf('[');
          final jsonEnd = content.lastIndexOf(']') + 1;
          if (jsonStart != -1 && jsonEnd > jsonStart) {
            final jsonString = content.substring(jsonStart, jsonEnd);
            final tags = List<String>.from(jsonDecode(jsonString));
            return tags.take(10).toList();
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing tags from description JSON: $e');
          }
        }
      }

      return [];
    } catch (e) {
      if (kDebugMode) {
        print('Error generating tags from description: $e');
      }
      return [];
    }
  }

  /// Summarize comments into key points
  /// Returns summary text
  Future<String?> summarizeComments(List<String> comments) async {
    try {
      if (comments.isEmpty) {
        return null;
      }

      if (_apiKey.isEmpty || _apiKey == 'YOUR_API_KEY') {
        return 'Có ${comments.length} bình luận. Nội dung chủ yếu về chủ đề của bài viết.';
      }

      final commentsText = comments.take(20).join('\n'); // Limit to 20 comments
      final prompt = 'Tóm tắt các bình luận sau thành 3-5 điểm chính (mỗi điểm 1 câu ngắn):\n\n$commentsText\n\nTrả về tóm tắt ngắn gọn:';

      Map<String, dynamic> requestBody;
      Uri requestUrl;

      if (_provider == 'gemini') {
        requestBody = {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {'maxOutputTokens': 300, 'temperature': 0.5},
        };
        requestUrl = Uri.parse('$_baseUrl/models/$_model:generateContent?key=$_apiKey');
      } else {
        requestBody = {
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content': 'Bạn là trợ lý AI chuyên tóm tắt nội dung. Tóm tắt ngắn gọn và súc tích.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 300,
          'temperature': 0.5,
        };
        requestUrl = Uri.parse('$_baseUrl/chat/completions');
      }

      final response = await http.post(requestUrl, headers: _headers, body: jsonEncode(requestBody));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content;

        if (_provider == 'gemini') {
          content = data['candidates'][0]['content']['parts'][0]['text'] as String;
        } else {
          if (data['choices'] != null && data['choices'].isNotEmpty) {
            content = data['choices'][0]['message']['content'] as String;
          } else {
            return null;
          }
        }

        return content.trim();
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error summarizing comments: $e');
      }
      return null;
    }
  }

  /// Evaluate content quality score (0-100)
  /// Returns quality score with suggestions
  Future<AIContentQuality> evaluateContentQuality({
    required String text,
    int? hashtagsCount,
    bool hasImage = false,
  }) async {
    try {
      if (_apiKey.isEmpty || _apiKey == 'YOUR_API_KEY') {
        return _ruleBasedQualityScore(text, hashtagsCount ?? 0, hasImage);
      }

      final prompt = 'Đánh giá chất lượng bài viết sau (0-100 điểm) dựa trên: độ dài, nội dung, hashtags (${hashtagsCount ?? 0}), có ảnh ($hashtagsCount):\n\n"$text"\n\nTrả về JSON: {"score": 0-100, "suggestions": ["gợi ý 1", "gợi ý 2"]}';

      Map<String, dynamic> requestBody;
      Uri requestUrl;

      if (_provider == 'gemini') {
        requestBody = {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {'maxOutputTokens': 200, 'temperature': 0.5},
        };
        requestUrl = Uri.parse('$_baseUrl/models/$_model:generateContent?key=$_apiKey');
      } else {
        requestBody = {
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content': 'Bạn là chuyên gia đánh giá chất lượng nội dung mạng xã hội.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 200,
          'temperature': 0.5,
        };
        requestUrl = Uri.parse('$_baseUrl/chat/completions');
      }

      final response = await http.post(requestUrl, headers: _headers, body: jsonEncode(requestBody));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content;

        if (_provider == 'gemini') {
          content = data['candidates'][0]['content']['parts'][0]['text'] as String;
        } else {
          if (data['choices'] != null && data['choices'].isNotEmpty) {
            content = data['choices'][0]['message']['content'] as String;
          } else {
            return _ruleBasedQualityScore(text, hashtagsCount ?? 0, hasImage);
          }
        }

        // Parse JSON
        try {
          final jsonStart = content.indexOf('{');
          final jsonEnd = content.lastIndexOf('}') + 1;
          if (jsonStart != -1 && jsonEnd > jsonStart) {
            final jsonString = content.substring(jsonStart, jsonEnd);
            final json = jsonDecode(jsonString);
            return AIContentQuality(
              score: (json['score'] as num?)?.toInt() ?? 50,
              suggestions: json['suggestions'] != null
                  ? List<String>.from(json['suggestions'])
                  : [],
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing quality JSON: $e');
          }
        }
      }

      return _ruleBasedQualityScore(text, hashtagsCount ?? 0, hasImage);
    } catch (e) {
      if (kDebugMode) {
        print('Error evaluating content quality: $e');
      }
      return _ruleBasedQualityScore(text, hashtagsCount ?? 0, hasImage);
    }
  }

  AIContentQuality _ruleBasedQualityScore(String text, int hashtagsCount, bool hasImage) {
    int score = 50;
    final suggestions = <String>[];

    // Length check
    if (text.length < 10) {
      score -= 20;
      suggestions.add('Nội dung quá ngắn, nên viết thêm');
    } else if (text.length > 500) {
      score -= 10;
      suggestions.add('Nội dung hơi dài, nên rút gọn');
    } else if (text.length >= 50 && text.length <= 200) {
      score += 10;
    }

    // Hashtags
    if (hashtagsCount == 0) {
      score -= 15;
      suggestions.add('Nên thêm hashtags để tăng độ tiếp cận');
    } else if (hashtagsCount >= 3 && hashtagsCount <= 10) {
      score += 10;
    } else if (hashtagsCount > 15) {
      score -= 10;
      suggestions.add('Quá nhiều hashtags, nên giảm xuống 5-10');
    }

    // Image
    if (hasImage) {
      score += 15;
    } else {
      suggestions.add('Thêm ảnh sẽ tăng engagement');
    }

    score = score.clamp(0, 100);
    return AIContentQuality(score: score, suggestions: suggestions);
  }
}

/// AI Content Suggestions Model
class AIContentSuggestions {
  final String caption;
  final List<String> hashtags;
  final String? translation;
  final String sentiment; // positive, neutral, negative

  AIContentSuggestions({required this.caption, required this.hashtags, this.translation, required this.sentiment});

  Map<String, dynamic> toMap() {
    return {'caption': caption, 'hashtags': hashtags, 'translation': translation, 'sentiment': sentiment};
  }

  factory AIContentSuggestions.fromMap(Map<String, dynamic> map) {
    return AIContentSuggestions(
      caption: map['caption'] ?? '',
      hashtags: List<String>.from(map['hashtags'] ?? []),
      translation: map['translation'],
      sentiment: map['sentiment'] ?? 'neutral',
    );
  }
}

/// AI Content Moderation Model
class AIContentModeration {
  final double score; // 0.0-1.0, higher = more problematic
  final bool isToxic;
  final bool isSpam;
  final String? reason;

  AIContentModeration({
    required this.score,
    required this.isToxic,
    required this.isSpam,
    this.reason,
  });

  bool get shouldBlock => score >= 0.7;
  bool get shouldWarn => score >= 0.5 && score < 0.7;
}

/// AI Content Quality Model
class AIContentQuality {
  final int score; // 0-100
  final List<String> suggestions;

  AIContentQuality({
    required this.score,
    required this.suggestions,
  });

  String get qualityLevel {
    if (score >= 80) return 'Xuất sắc';
    if (score >= 60) return 'Tốt';
    if (score >= 40) return 'Trung bình';
    return 'Cần cải thiện';
  }
}
