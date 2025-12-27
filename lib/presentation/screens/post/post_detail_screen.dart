import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../data/models/post_model.dart';
import '../../../data/models/comment_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/ai_content_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/post_card.dart';
import '../../widgets/comment_item.dart';
import '../../widgets/emoji_picker_widget.dart';
import '../../widgets/ai_smart_reply_widget.dart';
import '../../../core/utils/error_message_helper.dart';

class PostDetailScreen extends StatefulWidget {
  final PostModel post;

  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _commentController = TextEditingController();
  bool _isLoading = false;
  CommentModel? _replyingTo;
  String? _selectedGifUrl;
  String? _selectedEmoji;
  File? _selectedImage;
  bool _showEmojiPicker = false;
  String? _commentSummary;
  bool _isLoadingSummary = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    // Cho phép gửi nếu có text, GIF, emoji hoặc ảnh
    if (text.isEmpty && 
        _selectedGifUrl == null && 
        _selectedEmoji == null && 
        _selectedImage == null) return;

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    // AI Content Moderation - kiểm tra comment trước khi gửi
    if (text.isNotEmpty) {
      setState(() {
        _isLoading = true;
      });

      try {
        final aiService = AIContentService();
        final moderation = await aiService.moderateContent(text);
        
        if (moderation.shouldBlock) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  moderation.reason ?? 'Bình luận không phù hợp. Vui lòng chỉnh sửa.',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
            return;
          }
        } else if (moderation.shouldWarn) {
          if (mounted) {
            final shouldContinue = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Cảnh báo'),
                content: Text(
                  moderation.reason ?? 'Bình luận có thể không phù hợp. Bạn có muốn gửi?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Hủy'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Gửi'),
                  ),
                ],
              ),
            );
            if (shouldContinue != true) {
              setState(() {
                _isLoading = false;
              });
              return;
            }
          }
        }
      } catch (e) {
        // Nếu AI moderation fail, vẫn cho phép gửi
        debugPrint('AI moderation error: $e');
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? imageUrl;
      // Upload ảnh nếu có
      if (_selectedImage != null) {
        imageUrl = await _storageService.uploadCommentImage(
          _selectedImage!,
          widget.post.id,
          currentUser.id,
        );
      }

      final comment = CommentModel(
        id: '',
        postId: widget.post.id,
        userId: currentUser.id,
        content: text.isEmpty ? '' : text,
        gifUrl: _selectedGifUrl,
        imageUrl: imageUrl,
        emoji: _selectedEmoji,
        parentId: _replyingTo?.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _firestoreService.createComment(comment);
      _commentController.clear();
      setState(() {
        _replyingTo = null;
        _selectedGifUrl = null;
        _selectedEmoji = null;
        _selectedImage = null;
        _showEmojiPicker = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(
            e,
            defaultMessage: 'Không thể thêm bình luận',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleReply(CommentModel comment) {
    setState(() {
      _replyingTo = comment;
    });
    // Focus vào text field
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  void _openGifPicker() {
    // Một vài GIF mẫu; thực tế có thể dùng API tìm GIF
    const gifUrls = [
      'https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif',
      'https://media.giphy.com/media/l0HlNQ03J5JxX6lva/giphy.gif',
      'https://media.giphy.com/media/26tOZ42Mg6pbTUPHW/giphy.gif',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (ctx) => SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: gifUrls.length,
          itemBuilder: (context, index) {
            final url = gifUrls[index];
            return GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedGifUrl = url;
                });
                _addComment();
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(url, fit: BoxFit.cover),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _selectedGifUrl = null; // Clear GIF if image is selected
          _selectedEmoji = null; // Clear emoji if image is selected
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chọn ảnh: $e')),
        );
      }
    }
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
    } else {
      // Hiển thị emoji picker trong bottom sheet để tránh overflow
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: 350,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: EmojiPickerWidget(
            onEmojiSelected: (emoji) {
              Navigator.pop(context);
              _onEmojiSelected(emoji);
            },
          ),
        ),
      );
    }
  }

  void _onEmojiSelected(String emoji) {
    setState(() {
      _selectedEmoji = emoji;
      _selectedGifUrl = null; // Clear GIF if emoji is selected
      _selectedImage = null; // Clear image if emoji is selected
      _showEmojiPicker = false;
    });
  }

  Future<void> _summarizeComments() async {
    setState(() {
      _isLoadingSummary = true;
    });

    try {
      // Lấy tất cả comments
      final commentsSnapshot = await _firestoreService.getCommentsStream(widget.post.id).first;
      final comments = commentsSnapshot.map((c) => c.content).where((c) => c.isNotEmpty).toList();

      if (comments.length < 3) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cần ít nhất 3 comments để tóm tắt'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        setState(() {
          _isLoadingSummary = false;
        });
        return;
      }

      final aiService = AIContentService();
      final summary = await aiService.summarizeComments(comments);

      if (mounted) {
        setState(() {
          _commentSummary = summary;
          _isLoadingSummary = false;
        });

        if (summary != null) {
          // Hiển thị summary trong dialog
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.summarize, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  const Text('Tóm tắt Comments'),
                ],
              ),
              content: SingleChildScrollView(
                child: Text(
                  summary,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Đóng'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể tóm tắt comments. Vui lòng thử lại.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSummary = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bình luận'),
        actions: [
          // Comment Summarizer button
          StreamBuilder<List<CommentModel>>(
            stream: _firestoreService.getCommentsStream(widget.post.id),
            builder: (context, snapshot) {
              final commentsCount = snapshot.data?.length ?? 0;
              if (commentsCount < 3) {
                // Chỉ hiển thị nút nếu có ít nhất 3 comments
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: _isLoadingSummary
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.summarize),
                tooltip: 'Tóm tắt comments',
                onPressed: _isLoadingSummary ? null : _summarizeComments,
              );
            },
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          final appBarHeight = AppBar().preferredSize.height;
          final commentInputHeight = currentUser != null ? 120.0 : 0.0;
          final replyBarHeight = _replyingTo != null ? 48.0 : 0.0;
          final availableHeight = screenHeight - appBarHeight - commentInputHeight - replyBarHeight;
          
          return SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Post card - giới hạn chiều cao dựa trên không gian còn lại
                SizedBox(
                  height: availableHeight * 0.4, // Tối đa 40% màn hình
                  child: SingleChildScrollView(
                    child: PostCard(post: widget.post),
                  ),
                ),

                // Comment Summary (nếu có)
                if (_commentSummary != null)
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.summarize, size: 20, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tóm tắt Comments',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _commentSummary!,
                                style: const TextStyle(fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            setState(() {
                              _commentSummary = null;
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                // Comments list
                Expanded(
                  child: StreamBuilder<List<CommentModel>>(
                    stream: _firestoreService.getCommentsStream(widget.post.id),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 48),
                              const SizedBox(height: 16),
                              const Text(
                                'Không thể tải bình luận',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  'Lỗi: ${snapshot.error}',
                                  style: const TextStyle(color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text('Chưa có bình luận nào'));
                      }

                      final comments = snapshot.data!;

                      return ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          return CommentItem(
                            comment: comments[index],
                            onReply: _handleReply,
                          );
                        },
                      );
                    },
                  ),
                ),

                // Comment input section - fixed at bottom
                if (currentUser != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Hiển thị thông tin đang reply
                      if (_replyingTo != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          color: Colors.blue[50],
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Đang phản hồi bình luận...',
                                  style: TextStyle(
                                    color: Colors.blue[900],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _cancelReply,
                                color: Colors.blue[900],
                              ),
                            ],
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.2),
                              spreadRadius: 1,
                              blurRadius: 3,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // AI Smart Reply Suggestions - chỉ hiển thị khi comment vào post (không phải reply)
                            if (_replyingTo == null && widget.post.content.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: AISmartReplyWidget(
                                  originalText: widget.post.content,
                                  contextText: null,
                                  isReply: false,
                                  onReplySelected: (reply) {
                                    setState(() {
                                      _commentController.text = reply;
                                    });
                                  },
                                ),
                              ),
                            // Row chứa avatar, text field và nút send
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.grey[300],
                                  backgroundImage: currentUser.avatarUrl != null
                                      ? NetworkImage(currentUser.avatarUrl!)
                                      : null,
                                  child: currentUser.avatarUrl == null
                                      ? Text(
                                          currentUser.fullName[0].toUpperCase(),
                                          style: const TextStyle(fontSize: 14),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: TextField(
                                    controller: _commentController,
                                    style: const TextStyle(
                                      color: Colors.black,
                                    ),
                                    cursorColor: Colors.black,
                                    decoration: InputDecoration(
                                      hintText: _replyingTo != null
                                          ? 'Viết phản hồi...'
                                          : 'Viết bình luận...',
                                      hintStyle: TextStyle(color: Colors.grey[600]),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey[200],
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                    ),
                                    maxLines: 3,
                                    minLines: 1,
                                    textInputAction: TextInputAction.newline,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_isLoading)
                                  const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                else
                                  IconButton(
                                    icon: const Icon(Icons.send),
                                    onPressed: _addComment,
                                    color: Colors.blue,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                              ],
                            ),
                            // Row chứa các icon và preview ở dưới
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 50),
                                IconButton(
                                  icon: const Icon(Icons.emoji_emotions_outlined),
                                  color: Colors.grey[600],
                                  onPressed: _isLoading ? null : _toggleEmojiPicker,
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                  padding: EdgeInsets.zero,
                                  iconSize: 24,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.image_outlined),
                                  color: Colors.grey[600],
                                  onPressed: _isLoading ? null : _pickImage,
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                  padding: EdgeInsets.zero,
                                  iconSize: 24,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.gif_box_outlined),
                                  color: Colors.grey[600],
                                  onPressed: _isLoading ? null : _openGifPicker,
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                  padding: EdgeInsets.zero,
                                  iconSize: 24,
                                ),
                                if (_selectedEmoji != null)
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _selectedEmoji!,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                  ),
                                if (_selectedImage != null)
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.blue),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        _selectedImage!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
