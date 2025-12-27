import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../data/services/ai_content_service.dart';
import '../../data/services/storage_service.dart';

class AIContentAssistantWidget extends StatefulWidget {
  final String? text;
  final String? imageUrl; // Can be local file path or network URL
  final Function(String) onCaptionSelected;
  final Function(List<String>) onHashtagsSelected;
  final Function(String)? onTranslationSelected;

  const AIContentAssistantWidget({
    super.key,
    this.text,
    this.imageUrl,
    required this.onCaptionSelected,
    required this.onHashtagsSelected,
    this.onTranslationSelected,
  });

  @override
  State<AIContentAssistantWidget> createState() => _AIContentAssistantWidgetState();
}

class _AIContentAssistantWidgetState extends State<AIContentAssistantWidget> {
  final AIContentService _aiService = AIContentService();
  final StorageService _storageService = StorageService();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  AIContentSuggestions? _suggestions;
  bool _isLoading = false;
  bool _isExpanded = false;
  bool _isChatMode = false;
  bool _isChatLoading = false;
  Timer? _debounceTimer;
  String? _lastProcessedText;
  String? _lastProcessedImageUrl;
  List<Map<String, String>> _chatHistory = []; // [{role: 'user'/'assistant', content: '...'}]

  @override
  void initState() {
    super.initState();
    // Auto-load suggestions if text or image is provided
    if ((widget.text != null && widget.text!.isNotEmpty) || widget.imageUrl != null) {
      _loadSuggestions();
    }
  }

  @override
  void didUpdateWidget(AIContentAssistantWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Debounce: only reload if text or image actually changed
    if (widget.text != _lastProcessedText || widget.imageUrl != _lastProcessedImageUrl) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
        if (widget.text != _lastProcessedText || widget.imageUrl != _lastProcessedImageUrl) {
          _loadSuggestions();
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    if (kDebugMode) {
      debugPrint('AI Assistant: _loadSuggestions called');
      debugPrint('AI Assistant: text = ${widget.text}');
      debugPrint('AI Assistant: imageUrl = ${widget.imageUrl}');
      debugPrint('AI Assistant: _isLoading = $_isLoading');
      debugPrint('AI Assistant: _lastProcessedText = $_lastProcessedText');
      debugPrint('AI Assistant: _lastProcessedImageUrl = $_lastProcessedImageUrl');
    }

    // Nếu không có text và image, vẫn cho phép gọi để hiển thị gợi ý mặc định
    // Skip if already processing the same content
    if (widget.text == _lastProcessedText && widget.imageUrl == _lastProcessedImageUrl && _isLoading) {
      if (kDebugMode) {
        debugPrint('AI Assistant: Skipping - already processing same content');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('AI Assistant: Starting to load suggestions...');
    }

    setState(() {
      _isLoading = true;
      _isExpanded = true; // Tự động mở khi bắt đầu load
      _lastProcessedText = widget.text;
      _lastProcessedImageUrl = widget.imageUrl;
    });

    try {
      // For local file paths, upload to Cloudinary first to get a URL
      String? imageUrlForAPI = widget.imageUrl;
      
      if (imageUrlForAPI != null && !imageUrlForAPI.startsWith('http')) {
        // Local file - upload to Cloudinary first
        if (kDebugMode) {
          debugPrint('AI Assistant: Uploading local image to Cloudinary...');
        }
        
        try {
          if (kIsWeb) {
            // For web, read as bytes
            final file = File(imageUrlForAPI);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              imageUrlForAPI = await _storageService.uploadPostImageBytes(bytes);
              if (kDebugMode) {
                debugPrint('AI Assistant: Image uploaded to Cloudinary: $imageUrlForAPI');
              }
            } else {
              if (kDebugMode) {
                debugPrint('AI Assistant: Local file does not exist: $imageUrlForAPI');
              }
              imageUrlForAPI = null;
            }
          } else {
            // For mobile, use File directly
            final file = File(imageUrlForAPI);
            if (await file.exists()) {
              // Use a temporary postId for upload
              imageUrlForAPI = await _storageService.uploadPostImage(file, 'ai_temp', 0);
              if (kDebugMode) {
                debugPrint('AI Assistant: Image uploaded to Cloudinary: $imageUrlForAPI');
              }
            } else {
              if (kDebugMode) {
                debugPrint('AI Assistant: Local file does not exist: $imageUrlForAPI');
              }
              imageUrlForAPI = null;
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('AI Assistant: Error uploading image: $e');
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi upload ảnh: $e'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
          // Continue with null imageUrl - will use text-only suggestions
          imageUrlForAPI = null;
        }
      }

      if (kDebugMode) {
        debugPrint('AI Assistant: Calling generateSuggestions...');
        debugPrint('AI Assistant: imageUrlForAPI = $imageUrlForAPI');
      }

      final suggestions = await _aiService.generateSuggestions(
        text: widget.text ?? '',
        imageUrl: imageUrlForAPI,
      );

      if (kDebugMode) {
        debugPrint('AI Assistant: generateSuggestions returned');
        debugPrint('AI Assistant: suggestions = $suggestions');
        if (suggestions != null) {
          debugPrint('AI Assistant: caption = ${suggestions.caption}');
          debugPrint('AI Assistant: hashtags = ${suggestions.hashtags}');
          debugPrint('AI Assistant: translation = ${suggestions.translation}');
          debugPrint('AI Assistant: sentiment = ${suggestions.sentiment}');
        }
      }

      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _isLoading = false;
        });

        if (kDebugMode) {
          debugPrint('AI Assistant: State updated - _suggestions = $_suggestions, _isLoading = false');
        }
        
        // Nếu không có suggestions, hiển thị thông báo
        if (suggestions == null && (widget.text == null || widget.text!.trim().isEmpty) && widget.imageUrl == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vui lòng nhập nội dung hoặc chọn ảnh để nhận gợi ý từ AI'),
              duration: Duration(seconds: 2),
            ),
          );
        } else if (suggestions != null) {
          // Hiển thị thông báo thành công
          if (kDebugMode) {
            debugPrint('AI Assistant: Suggestions loaded successfully - Caption: ${suggestions.caption}, Hashtags: ${suggestions.hashtags.length}');
          }
        } else if (suggestions == null) {
          if (kDebugMode) {
            debugPrint('AI Assistant: WARNING - suggestions is null!');
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể tạo gợi ý. Vui lòng thử lại.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải gợi ý AI: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        debugPrint('AI Content Assistant Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isExpanded && !_isLoading && _suggestions == null) {
      return _buildCollapsedButton();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Gợi ý từ AI',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blue,
                ),
              ),
              const Spacer(),
              // Toggle button giữa Suggestions và Chat
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _isChatMode = false;
                        _isExpanded = true;
                      });
                    },
                    icon: Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: !_isChatMode ? Colors.blue : Colors.grey,
                    ),
                    label: Text(
                      'Gợi ý',
                      style: TextStyle(
                        fontSize: 12,
                        color: !_isChatMode ? Colors.blue : Colors.grey,
                        fontWeight: !_isChatMode ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _isChatMode = true;
                        _isExpanded = true;
                      });
                    },
                    icon: Icon(
                      Icons.chat_bubble_outline,
                      size: 16,
                      color: _isChatMode ? Colors.blue : Colors.grey,
                    ),
                    label: Text(
                      'Chat',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isChatMode ? Colors.blue : Colors.grey,
                        fontWeight: _isChatMode ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (_isExpanded) ...[
            if (_isChatMode) ...[
              // Chat mode UI
              _buildChatInterface(),
            ] else ...[
              // Suggestions mode UI
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_suggestions != null) ...[
                if (kDebugMode)
                  Text(
                    'DEBUG: Caption length = ${_suggestions!.caption.length}, Hashtags = ${_suggestions!.hashtags.length}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                const SizedBox(height: 12),
                _buildCaptionSection(),
                const SizedBox(height: 12),
                _buildHashtagsSection(),
                if (_suggestions!.translation != null) ...[
                  const SizedBox(height: 12),
                  _buildTranslationSection(),
                ],
                const SizedBox(height: 12),
                _buildSentimentSection(),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCollapsedButton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: ElevatedButton.icon(
        onPressed: _isLoading
            ? null
            : () {
                if (kDebugMode) {
                  debugPrint('AI Assistant: Button pressed!');
                }
                _loadSuggestions();
              },
        icon: _isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome, size: 18),
        label: Text(_isLoading ? 'Đang tải...' : 'Nhận gợi ý từ AI'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[100],
          foregroundColor: Colors.blue[900],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          disabledBackgroundColor: Colors.blue[50],
        ),
      ),
    );
  }

  Widget _buildCaptionSection() {
    return _buildSuggestionCard(
      title: 'Caption cải thiện',
      content: _suggestions!.caption,
      onUse: () {
        widget.onCaptionSelected(_suggestions!.caption);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã áp dụng caption'),
            duration: Duration(seconds: 1),
          ),
        );
      },
    );
  }

  Widget _buildHashtagsSection() {
    return _buildSuggestionCard(
      title: 'Hashtags gợi ý',
      content: _suggestions!.hashtags.join(' '),
      onUse: () {
        widget.onHashtagsSelected(_suggestions!.hashtags);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã thêm hashtags'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      isHashtags: true,
    );
  }

  Widget _buildTranslationSection() {
    return _buildSuggestionCard(
      title: 'Bản dịch',
      content: _suggestions!.translation!,
      onUse: widget.onTranslationSelected != null
          ? () {
              widget.onTranslationSelected!(_suggestions!.translation!);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã áp dụng bản dịch'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          : null,
    );
  }

  Widget _buildSentimentSection() {
    final sentiment = _suggestions!.sentiment;
    final sentimentText = {
      'positive': 'Tích cực 😊',
      'neutral': 'Trung tính 😐',
      'negative': 'Tiêu cực 😔',
    }[sentiment] ?? 'Trung tính';

    final sentimentColor = {
      'positive': Colors.green,
      'neutral': Colors.grey,
      'negative': Colors.red,
    }[sentiment] ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          const Text(
            'Cảm xúc: ',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sentimentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              sentimentText,
              style: TextStyle(
                color: sentimentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard({
    required String title,
    required String content,
    required VoidCallback? onUse,
    bool isHashtags = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (onUse != null)
                TextButton(
                  onPressed: onUse,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Dùng',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            content,
            style: TextStyle(
              fontSize: 14,
              color: isHashtags ? Colors.blue : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInterface() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Chat messages area
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: _chatHistory.isEmpty
                ? SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 40, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            'Chat với AI để yêu cầu viết lại caption, hashtags hoặc các gợi ý khác',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: [
                              _buildQuickActionChip('Viết lại caption ngắn gọn hơn'),
                              _buildQuickActionChip('Thêm hashtags phù hợp'),
                              _buildQuickActionChip('Viết caption vui vẻ hơn'),
                              _buildQuickActionChip('Dịch sang tiếng Anh'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _chatScrollController,
                    padding: const EdgeInsets.all(8),
                    shrinkWrap: true,
                    itemCount: _chatHistory.length + (_isChatLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _chatHistory.length) {
                        // Loading indicator
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final message = _chatHistory[index];
                      final isUser = message['role'] == 'user';
                      return _buildChatMessage(
                        message: message['content'] ?? '',
                        isUser: isUser,
                      );
                    },
                  ),
            ),
          ),
        // Chat input area
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: InputDecoration(
                    hintText: 'Nhập yêu cầu của bạn...',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    hintStyle: TextStyle(color: Colors.grey[400]),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendChatMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _isChatLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: Colors.blue),
                onPressed: _isChatLoading ? null : _sendChatMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatMessage({required String message, required bool isUser}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: Colors.blue[100],
              child: const Icon(Icons.auto_awesome, size: 14, color: Colors.blue),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue[100] : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: isUser ? Colors.blue[900] : Colors.black87,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 12,
              backgroundColor: Colors.grey[300],
              child: const Icon(Icons.person, size: 14, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionChip(String text) {
    return ActionChip(
      label: Text(
        text,
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () {
        _chatController.text = text;
        _sendChatMessage();
      },
      backgroundColor: Colors.blue[50],
      labelStyle: const TextStyle(color: Colors.blue),
    );
  }

  Future<void> _sendChatMessage() async {
    final message = _chatController.text.trim();
    if (message.isEmpty || _isChatLoading) return;

    // Add user message to history
    setState(() {
      _chatHistory.add({'role': 'user', 'content': message});
      _isChatLoading = true;
      _chatController.clear();
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      // Prepare context
      String? imageUrlForAPI = widget.imageUrl;
      
      // Upload local image if needed
      if (imageUrlForAPI != null && !imageUrlForAPI.startsWith('http')) {
        try {
          if (kIsWeb) {
            final file = File(imageUrlForAPI);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              imageUrlForAPI = await _storageService.uploadPostImageBytes(bytes);
            } else {
              imageUrlForAPI = null;
            }
          } else {
            final file = File(imageUrlForAPI);
            if (await file.exists()) {
              imageUrlForAPI = await _storageService.uploadPostImage(file, 'ai_temp', 0);
            } else {
              imageUrlForAPI = null;
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('AI Chat: Error uploading image: $e');
          }
          imageUrlForAPI = null;
        }
      }

      // Prepare conversation history (exclude current message)
      final history = _chatHistory.length > 1
          ? _chatHistory.sublist(0, _chatHistory.length - 1)
          : <Map<String, String>>[];

      // Call AI chat
      final response = await _aiService.chatWithAI(
        userMessage: message,
        contextText: widget.text,
        imageUrl: imageUrlForAPI,
        conversationHistory: history,
      );

      if (mounted) {
        setState(() {
          if (response != null) {
            _chatHistory.add({'role': 'assistant', 'content': response});
          } else {
            _chatHistory.add({
              'role': 'assistant',
              'content': 'Xin lỗi, tôi không thể phản hồi lúc này. Vui lòng thử lại.',
            });
          }
          _isChatLoading = false;
        });

        // Scroll to bottom after response
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScrollController.hasClients) {
            _chatScrollController.animateTo(
              _chatScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatHistory.add({
            'role': 'assistant',
            'content': 'Xin lỗi, đã xảy ra lỗi: ${e.toString()}',
          });
          _isChatLoading = false;
        });
      }
      if (kDebugMode) {
        debugPrint('AI Chat Error: $e');
      }
    }
  }
}

