import 'package:flutter/material.dart';
import '../../data/services/ai_content_service.dart';

/// Widget hiển thị gợi ý trả lời thông minh từ AI
class AISmartReplyWidget extends StatefulWidget {
  final String originalText;
  final String? contextText;
  final bool isReply;
  final Function(String) onReplySelected;

  const AISmartReplyWidget({
    super.key,
    required this.originalText,
    this.contextText,
    this.isReply = false,
    required this.onReplySelected,
  });

  @override
  State<AISmartReplyWidget> createState() => _AISmartReplyWidgetState();
}

class _AISmartReplyWidgetState extends State<AISmartReplyWidget> {
  final AIContentService _aiService = AIContentService();
  List<String> _suggestions = [];
  bool _isLoading = false;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    if (widget.originalText.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final suggestions = await _aiService.generateSmartReplies(
        originalText: widget.originalText,
        contextText: widget.contextText,
        isReply: widget.isReply,
      );

      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _isLoading = false;
          if (suggestions.isNotEmpty) {
            _isExpanded = true;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              'AI đang tạo gợi ý...',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (_suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: Colors.blue[600]),
              const SizedBox(width: 4),
              Text(
                'Gợi ý trả lời',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue[600],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions.map((suggestion) {
                return ActionChip(
                  label: Text(
                    suggestion,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onPressed: () {
                    widget.onReplySelected(suggestion);
                  },
                  backgroundColor: Colors.blue[50],
                  labelStyle: TextStyle(color: Colors.blue[700]),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

