import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/comment_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/reaction_model.dart';
import '../../data/services/user_service.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/libretranslate_service.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';

class CommentItem extends StatefulWidget {
  final CommentModel comment;
  final Function(CommentModel)? onReply;

  const CommentItem({
    super.key,
    required this.comment,
    this.onReply,
  });

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  final UserService _userService = UserService();
  final FirestoreService _firestoreService = FirestoreService();
  final LibreTranslateService _translateService = LibreTranslateService();
  UserModel? _commentUser;
  ReactionType? _userReaction;
  Map<ReactionType, int> _reactionCounts = {};
  int _totalReactions = 0;
  bool _showReplies = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkUserReaction();
    _loadReactionCounts();
  }

  Future<void> _loadUserData() async {
    final user = await _userService.getUserById(widget.comment.userId);
    if (mounted) {
      setState(() {
        _commentUser = user;
      });
    }
  }

  Future<void> _checkUserReaction() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final reaction = await _firestoreService.getUserCommentReaction(
      widget.comment.id,
      currentUser.id,
    );
    if (mounted) {
      setState(() {
        _userReaction = reaction;
      });
    }
  }

  Future<void> _loadReactionCounts() async {
    final counts = await _firestoreService.getCommentReactions(widget.comment.id);
    if (mounted) {
      setState(() {
        _reactionCounts = counts;
        _totalReactions = counts.values.fold(0, (sum, count) => sum + count);
      });
    }
  }

  Future<void> _openReactionSheet() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    // Nếu đã thả cảm xúc rồi, tap lần nữa sẽ gỡ cảm xúc hiện tại
    if (_userReaction != null) {
      await _reactToComment(_userReaction!);
      return;
    }

    final selected = await showModalBottomSheet<ReactionType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: ReactionType.values.map((type) {
                return GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop(type);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      type.emoji,
                      style: const TextStyle(fontSize: 30),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await _reactToComment(selected);
    }
  }

  Future<void> _reactToComment(ReactionType type) async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final previousReaction = _userReaction;
    final wasReacted = previousReaction != null;

    if (mounted) {
      setState(() {
        _userReaction = type;
        if (!wasReacted) {
          _totalReactions++;
          _reactionCounts[type] = (_reactionCounts[type] ?? 0) + 1;
        } else if (previousReaction != type) {
          _reactionCounts[previousReaction] =
              (_reactionCounts[previousReaction] ?? 1) - 1;
          if (_reactionCounts[previousReaction] == 0) {
            _reactionCounts.remove(previousReaction);
          }
          _reactionCounts[type] = (_reactionCounts[type] ?? 0) + 1;
        } else {
          _totalReactions--;
          _reactionCounts[type] = (_reactionCounts[type] ?? 1) - 1;
          if (_reactionCounts[type] == 0) {
            _reactionCounts.remove(type);
          }
          _userReaction = null;
        }
      });
    }

    try {
      await _firestoreService.reactToComment(
        widget.comment.id,
        currentUser.id,
        type,
      );
      // Reload reaction counts and user reaction to ensure UI is in sync
      await Future.wait([
        _loadReactionCounts(),
        _checkUserReaction(),
      ]);
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          _userReaction = previousReaction;
        });
      }
      await _loadReactionCounts();
      await _checkUserReaction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  Future<void> _showEditCommentDialog() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null || currentUser.id != widget.comment.userId) return;

    final TextEditingController editController = TextEditingController(
      text: widget.comment.content,
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chỉnh sửa bình luận'),
        content: TextField(
          controller: editController,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Nhập nội dung bình luận...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              if (editController.text.trim().isNotEmpty) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (result == true && editController.text.trim().isNotEmpty) {
      try {
        final updatedComment = widget.comment.copyWith(
          content: editController.text.trim(),
          updatedAt: DateTime.now(),
        );
        await _firestoreService.updateComment(updatedComment);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã cập nhật bình luận'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi cập nhật bình luận: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDeleteCommentDialog() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null || currentUser.id != widget.comment.userId) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa bình luận'),
        content: const Text('Bạn có chắc chắn muốn xóa bình luận này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firestoreService.deleteComment(widget.comment.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã xóa bình luận'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi xóa bình luận: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ngày trước';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} phút trước';
    } else {
      return 'Vừa xong';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReply = widget.comment.parentId != null;
    return Padding(
      padding: EdgeInsets.only(
        left: isReply ? 40 : 12,
        right: 12,
        top: 8,
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey[300],
            backgroundImage: _commentUser?.avatarUrl != null
                ? NetworkImage(_commentUser!.avatarUrl!)
                : null,
            child: _commentUser?.avatarUrl == null
                ? Text(
                    _commentUser?.fullName[0].toUpperCase() ?? 'U',
                    style: const TextStyle(fontSize: 14),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          // Comment content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white, // bong bóng comment màu trắng
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _commentUser?.fullName ?? 'Người dùng',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.black, // Dark text on light bubble
                              ),
                            ),
                          ),
                          // Menu options (chỉ hiển thị cho chủ bình luận)
                          Builder(
                            builder: (context) {
                              final authProvider = context.watch<AuthProvider>();
                              final currentUser = authProvider.currentUser;
                              final isOwnComment = currentUser != null && 
                                  currentUser.id == widget.comment.userId;
                              
                              if (!isOwnComment) return const SizedBox.shrink();
                              
                              return PopupMenuButton<String>(
                                icon: const Icon(
                                  Icons.more_vert,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                padding: EdgeInsets.zero,
                                onSelected: (value) async {
                                  if (value == 'edit') {
                                    await _showEditCommentDialog();
                                  } else if (value == 'delete') {
                                    await _showDeleteCommentDialog();
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 18),
                                        SizedBox(width: 8),
                                        Text('Chỉnh sửa'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 18, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Xóa', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      if (widget.comment.emoji != null) ...[
                        Text(
                          widget.comment.emoji!,
                          style: const TextStyle(fontSize: 32),
                        ),
                        if (widget.comment.content.isNotEmpty)
                          const SizedBox(height: 4),
                      ],
                      if (widget.comment.content.isNotEmpty) ...[
                        if (widget.comment.emoji == null) const SizedBox(height: 4),
                        Consumer<LanguageProvider>(
                          builder: (context, languageProvider, _) {
                            return FutureBuilder<String>(
                              future: _getTranslatedContent(
                                widget.comment.content,
                                languageProvider,
                              ),
                              builder: (context, snapshot) {
                                final displayText = snapshot.data ?? widget.comment.content;
                                return Text(
                                  displayText,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black, // Ensure content is visible
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                      if (widget.comment.imageUrl != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            widget.comment.imageUrl!,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 200,
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image),
                              );
                            },
                          ),
                        ),
                      ],
                      if (widget.comment.gifUrl != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            widget.comment.gifUrl!,
                            height: 120,
                            width: 160,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Reaction counts (if any)
                if (_totalReactions > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        ..._reactionCounts.entries.take(3).map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              entry.key.emoji,
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }),
                        const SizedBox(width: 4),
                        Text(
                          _totalReactions.toString(),
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _openReactionSheet,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_userReaction != null) ...[
                            Text(
                              _userReaction!.emoji,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _userReaction?.name ?? 'Thích',
                            style: TextStyle(
                              fontSize: 12,
                              color: _userReaction != null ? Colors.blue : null,
                              fontWeight: _userReaction != null
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (widget.onReply != null) {
                          widget.onReply!(widget.comment);
                        }
                      },
                      child: const Text(
                        'Phản hồi',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    // Hiển thị số lượng replies nếu có
                    StreamBuilder<List<CommentModel>>(
                      stream: _firestoreService.getRepliesStream(widget.comment.id),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                          final replyCount = snapshot.data!.length;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _showReplies = !_showReplies;
                              });
                            },
                            child: Text(
                              '${_showReplies ? 'Ẩn' : 'Xem'} $replyCount phản hồi',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    Text(
                      _formatDate(widget.comment.createdAt),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    // Hiển thị "Đã chỉnh sửa" nếu bình luận đã được chỉnh sửa
                    if (widget.comment.updatedAt.isAfter(widget.comment.createdAt.add(const Duration(seconds: 1))))
                      Text(
                        ' • Đã chỉnh sửa',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
                // Hiển thị replies nếu có
                if (_showReplies)
                  StreamBuilder<List<CommentModel>>(
                    stream: _firestoreService.getRepliesStream(widget.comment.id),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 16, top: 8),
                          child: Column(
                            children: snapshot.data!.map((reply) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: CommentItem(
                                  comment: reply,
                                  onReply: widget.onReply,
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Get translated content if auto-translate is enabled
  Future<String> _getTranslatedContent(
    String originalText,
    LanguageProvider languageProvider,
  ) async {
    // Nếu không bật auto-translate, trả về text gốc
    if (!languageProvider.autoTranslate) {
      return originalText;
    }

    // Nếu ngôn ngữ hiện tại là tiếng Việt, không cần dịch
    final currentLang = languageProvider.currentLanguageCode;
    if (currentLang == 'vi') {
      return originalText;
    }

    try {
      // Dịch từ tiếng Việt sang ngôn ngữ đích
      final translated = await _translateService.translate(
        text: originalText,
        source: 'vi',
        target: currentLang,
      );

      return translated;
    } catch (e) {
      debugPrint('Error translating comment content: $e');
      return originalText; // Trả về text gốc nếu lỗi
    }
  }
}


