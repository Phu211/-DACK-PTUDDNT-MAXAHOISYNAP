import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/conversation_model.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/group_model.dart';
import '../../../data/services/message_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/presence_service.dart';
import '../../../data/services/group_service.dart';
import '../../../data/services/settings_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../../core/utils/error_message_helper.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import 'group_chat_screen.dart';

class MessagesListScreen extends StatefulWidget {
  final String? postIdToShare;

  const MessagesListScreen({super.key, this.postIdToShare});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  final FriendService _friendService = FriendService();
  final PresenceService _presenceService = PresenceService();
  final GroupService _groupService = GroupService();
  final MessageService _messageService = MessageService();
  final UserService _userService = UserService();
  List<String> _friendIds = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  final TextStyle _highlightStyle = const TextStyle(
    color: Colors.orangeAccent,
    fontWeight: FontWeight.w700,
  );
  bool _activityStatusEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _loadActivityStatusSetting();
  }

  Future<void> _loadActivityStatusSetting() async {
    final enabled = await SettingsService.isActivityStatusEnabled();
    if (mounted) {
      setState(() {
        _activityStatusEnabled = enabled;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser != null) {
      final friends = await _friendService.getFriends(currentUser.id);
      if (mounted) {
        setState(() {
          _friendIds = friends;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập')));
    }

    // Chỉ lấy online users nếu activity status được bật
    final onlineStream = (_friendIds.isEmpty || !_activityStatusEnabled)
        ? Stream<List<String>>.value(const [])
        : _presenceService.getOnlineUsers(_friendIds);

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Tin nhắn',
          style: TextStyle(
            color: theme.textTheme.titleLarge?.color,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add, color: AppColors.primary),
            tooltip: 'Tạo nhóm',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NewChatScreen(isGroupMode: true),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: AppColors.primary,
            ),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSearching)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: theme.cardColor,
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm cuộc trò chuyện...',
                  hintStyle: TextStyle(color: theme.textTheme.bodySmall?.color),
                  prefixIcon: Icon(
                    Icons.search,
                    color: theme.iconTheme.color?.withOpacity(0.6),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: theme.iconTheme.color?.withOpacity(0.6),
                          ),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.primary.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          // Online users section
          _buildOnlineUsersSection(context, onlineStream),

          // Conversations list
          Expanded(
            child: StreamBuilder<List<ConversationModel>>(
              stream: _messageService.getConversations(currentUser.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: theme.primaryColor),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Lỗi: ${snapshot.error}',
                      style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.message_outlined,
                          size: 64,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Chưa có cuộc trò chuyện nào',
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Nhấn nút + để bắt đầu cuộc trò chuyện mới',
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final conversations = snapshot.data!;

                // Sắp xếp: conversations đã ghim ở đầu, sau đó là các conversations khác
                final sortedConversations =
                    List<ConversationModel>.from(conversations)..sort((a, b) {
                      // Conversations đã ghim luôn ở đầu
                      if (a.isPinned && !b.isPinned) return -1;
                      if (!a.isPinned && b.isPinned) return 1;
                      // Nếu cả 2 đều ghim hoặc không ghim, sắp xếp theo thời gian tin nhắn cuối (mới nhất trước)
                      return b.lastMessageTime.compareTo(a.lastMessageTime);
                    });
                final query = _searchController.text.trim().toLowerCase();

                // Lọc theo search (tên, username, last message)
                final filtered = sortedConversations.where((conversation) {
                  // Group conversation
                  if (conversation.type == 'group' &&
                      conversation.groupId != null) {
                    final lastMsg = (conversation.lastMessageContent ?? '')
                        .toLowerCase();
                    if (query.isEmpty) return true;
                    if (lastMsg.contains(query)) return true;
                    return true; // Sẽ check group name trong builder
                  }

                  // Direct conversation
                  final otherUserId = conversation.getOtherUserId(
                    currentUser.id,
                  );
                  if (otherUserId == null) return false;
                  final lastMsg = (conversation.lastMessageContent ?? '')
                      .toLowerCase();
                  if (query.isEmpty) return true;
                  if (lastMsg.contains(query)) return true;
                  return true; // tiếp tục để check trong builder
                }).toList();

                if (_isSearching && filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Không tìm thấy cuộc trò chuyện',
                        style: TextStyle(
                          color: theme.textTheme.bodySmall?.color,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }

                return StreamBuilder<List<String>>(
                  stream: onlineStream,
                  builder: (context, onlineSnapshot) {
                    final onlineSet = (onlineSnapshot.data ?? const <String>[])
                        .toSet();

                    // Batch-load all other users once per list rebuild.
                    final otherUserIds = <String>{};
                    for (final c in filtered) {
                      if (c.type == 'group') continue;
                      final otherId = c.getOtherUserId(currentUser.id);
                      if (otherId != null) otherUserIds.add(otherId);
                    }

                    return FutureBuilder<List<UserModel>>(
                      future: otherUserIds.isEmpty
                          ? Future.value(const <UserModel>[])
                          : _userService.getUsersByIds(otherUserIds.toList()),
                      builder: (context, usersSnapshot) {
                        if (usersSnapshot.connectionState ==
                                ConnectionState.waiting &&
                            (usersSnapshot.data == null ||
                                usersSnapshot.data!.isEmpty)) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.black,
                            ),
                          );
                        }

                        final users = usersSnapshot.data ?? const <UserModel>[];
                        final userMap = <String, UserModel>{
                          for (final u in users) u.id: u,
                        };

                        return ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final conversation = filtered[index];
                            final unreadCount = conversation.getUnreadCount(
                              currentUser.id,
                            );
                            final isLastMessageFromMe =
                                conversation.lastMessageSenderId ==
                                currentUser.id;

                            // Group conversation
                            if (conversation.type == 'group' &&
                                conversation.groupId != null) {
                              return FutureBuilder<GroupModel?>(
                                future: _groupService.getGroup(
                                  conversation.groupId!,
                                ),
                                builder: (context, groupSnapshot) {
                                  if (!groupSnapshot.hasData ||
                                      groupSnapshot.data == null) {
                                    return const SizedBox.shrink();
                                  }

                                  final group = groupSnapshot.data!;
                                  final groupName = group.name.toLowerCase();
                                  final lastMsg =
                                      (conversation.lastMessageContent ?? '')
                                          .toLowerCase();

                                  // Filter by search query
                                  if (query.isNotEmpty) {
                                    if (!groupName.contains(query) &&
                                        !lastMsg.contains(query)) {
                                      return const SizedBox.shrink();
                                    }
                                  }

                                  return _buildGroupConversationTile(
                                    context: context,
                                    conversation: conversation,
                                    group: group,
                                    currentUser: currentUser,
                                    messageService: _messageService,
                                    unreadCount: unreadCount,
                                    isLastMessageFromMe: isLastMessageFromMe,
                                    query: query,
                                    highlightStyle: _highlightStyle,
                                  );
                                },
                              );
                            }

                            // Direct conversation
                            final otherUserId = conversation.getOtherUserId(
                              currentUser.id,
                            );
                            if (otherUserId == null) {
                              return const SizedBox.shrink();
                            }

                            final otherUser = userMap[otherUserId];
                            if (otherUser == null) {
                              // Fallback: cached user not ready yet
                              return const SizedBox.shrink();
                            }

                            final nickname =
                                conversation.nicknames[otherUser.id];
                            final displayName =
                                (nickname != null && nickname.isNotEmpty)
                                ? nickname
                                : otherUser.fullName;

                            // Filter by search query (name, username, last message, full text)
                            final name = displayName.toLowerCase();
                            final username = otherUser.username.toLowerCase();
                            final lastMsg =
                                (conversation.lastMessageContent ?? '')
                                    .toLowerCase();
                            if (query.isNotEmpty) {
                              final baseMatch =
                                  name.contains(query) ||
                                  username.contains(query) ||
                                  lastMsg.contains(query);
                              if (!baseMatch) {
                                return FutureBuilder<List<MessageModel>>(
                                  future: _messageService.searchMessages(
                                    conversationId: conversation.id,
                                    query: query,
                                    limit: 80,
                                  ),
                                  builder: (context, searchSnap) {
                                    if (searchSnap.connectionState ==
                                        ConnectionState.waiting) {
                                      return const SizedBox.shrink();
                                    }
                                    final results = searchSnap.data ?? [];
                                    if (results.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return _conversationTile(
                                      context: context,
                                      conversation: conversation,
                                      otherUser: otherUser,
                                      currentUser: currentUser,
                                      messageService: _messageService,
                                      unreadCount: unreadCount,
                                      isLastMessageFromMe: isLastMessageFromMe,
                                      query: query,
                                      highlightStyle: _highlightStyle,
                                      overridePreview: results.first,
                                      nickname: nickname,
                                      displayName: displayName,
                                      isOnline: onlineSet.contains(
                                        otherUser.id,
                                      ),
                                    );
                                  },
                                );
                              }
                            }

                            return _conversationTile(
                              context: context,
                              conversation: conversation,
                              otherUser: otherUser,
                              currentUser: currentUser,
                              messageService: _messageService,
                              unreadCount: unreadCount,
                              isLastMessageFromMe: isLastMessageFromMe,
                              query: query,
                              highlightStyle: _highlightStyle,
                              nickname: nickname,
                              displayName: displayName,
                              isOnline: onlineSet.contains(otherUser.id),
                              onLongPress: () => _showConversationOptionsDialog(
                                context,
                                conversation,
                                otherUser,
                                currentUser,
                                _messageService,
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const NewChatScreen(isGroupMode: false),
            ),
          );
        },
        backgroundColor: theme.primaryColor,
        child: Icon(Icons.message, color: theme.colorScheme.onPrimary),
      ),
    );
  }

  Widget _buildOnlineUsersSection(
    BuildContext context,
    Stream<List<String>> onlineStream,
  ) {
    if (_friendIds.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: StreamBuilder<List<String>>(
        stream: onlineStream,
        builder: (context, onlineSnapshot) {
          if (!onlineSnapshot.hasData || onlineSnapshot.data!.isEmpty) {
            return const SizedBox.shrink();
          }

          final onlineUserIds = onlineSnapshot.data!;
          return FutureBuilder<List<UserModel>>(
            future: _userService.getUsersByIds(onlineUserIds),
            builder: (context, usersSnap) {
              final users = usersSnap.data ?? const <UserModel>[];
              if (users.isEmpty) return const SizedBox.shrink();

              final map = <String, UserModel>{for (final u in users) u.id: u};
              final ordered = onlineUserIds
                  .map((id) => map[id])
                  .whereType<UserModel>()
                  .toList();

              if (ordered.isEmpty) return const SizedBox.shrink();

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: ordered.length,
                itemBuilder: (context, index) {
                  final user = ordered[index];
                  return GestureDetector(
                    onTap: () async {
                      // Nếu có postIdToShare, gửi message với post link trước
                      if (widget.postIdToShare != null) {
                        final authProvider = context.read<AuthProvider>();
                        final currentUser = authProvider.currentUser;
                        if (currentUser != null) {
                          try {
                            final postLink =
                                'https://synap.app/post/${widget.postIdToShare}';
                            final shareMessage = MessageModel(
                              id: '',
                              senderId: currentUser.id,
                              receiverId: user.id,
                              content: postLink,
                              createdAt: DateTime.now(),
                            );
                            await _messageService.sendMessage(shareMessage);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ErrorMessageHelper.getErrorMessage(
                                      e,
                                      defaultMessage: 'Không thể gửi bài viết',
                                    ),
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      }

                      if (mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(otherUser: user),
                          ),
                        );
                      }
                    },
                    child: Container(
                      width: 80,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundImage: user.avatarUrl != null
                                    ? NetworkImage(user.avatarUrl!)
                                    : null,
                                child: user.avatarUrl == null
                                    ? Text(
                                        user.fullName[0].toUpperCase(),
                                        style: TextStyle(
                                          color:
                                              theme.textTheme.bodyLarge?.color,
                                          fontSize: 20,
                                        ),
                                      )
                                    : null,
                              ),
                              // Chấm xanh để chỉ online - chỉ hiển thị khi setting được bật
                              if (_activityStatusEnabled)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF31A24C),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.fullName,
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showConversationOptionsDialog(
    BuildContext context,
    ConversationModel conversation,
    UserModel otherUser,
    UserModel currentUser,
    MessageService messageService,
  ) async {
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                conversation.isPinned
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                color: conversation.isPinned
                    ? Colors.orange
                    : theme.iconTheme.color,
              ),
              title: Text(
                conversation.isPinned ? 'Bỏ ghim đoạn chat' : 'Ghim đoạn chat',
                style: TextStyle(
                  color: conversation.isPinned
                      ? Colors.orange
                      : theme.textTheme.bodyLarge?.color,
                ),
              ),
              onTap: () => Navigator.pop(
                context,
                conversation.isPinned ? 'unpin' : 'pin',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.red),
              title: const Text(
                'Xóa đoạn chat',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            ListTile(
              leading: Icon(
                Icons.cancel,
                color: theme.iconTheme.color?.withOpacity(0.6),
              ),
              title: Text(
                'Hủy',
                style: TextStyle(color: theme.textTheme.bodySmall?.color),
              ),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );

    if (result == 'pin') {
      await _pinConversation(
        context,
        conversation,
        currentUser,
        messageService,
      );
    } else if (result == 'unpin') {
      await _unpinConversation(
        context,
        conversation,
        currentUser,
        messageService,
      );
    } else if (result == 'delete') {
      await _showDeleteConversationDialog(
        context,
        conversation,
        currentUser,
        messageService,
      );
    }
  }

  Future<void> _pinConversation(
    BuildContext context,
    ConversationModel conversation,
    UserModel currentUser,
    MessageService messageService,
  ) async {
    try {
      final otherUserId = conversation.getOtherUserId(currentUser.id);
      if (otherUserId == null) return;

      await messageService.pinConversation(
        currentUser.id,
        otherUserId,
        currentUser.id,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã ghim đoạn chat'),
            backgroundColor: Colors.black,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    }
  }

  Future<void> _unpinConversation(
    BuildContext context,
    ConversationModel conversation,
    UserModel currentUser,
    MessageService messageService,
  ) async {
    try {
      final otherUserId = conversation.getOtherUserId(currentUser.id);
      if (otherUserId == null) return;

      await messageService.unpinConversation(
        currentUser.id,
        otherUserId,
        currentUser.id,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã bỏ ghim đoạn chat'),
            backgroundColor: Colors.black,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    }
  }

  Future<void> _showDeleteConversationDialog(
    BuildContext context,
    ConversationModel conversation,
    UserModel currentUser,
    MessageService messageService,
  ) async {
    final theme = Theme.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: Text(
          'Xóa đoạn chat',
          style: TextStyle(color: theme.textTheme.titleLarge?.color),
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa toàn bộ đoạn chat này? Hành động này không thể hoàn tác.',
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Hủy',
              style: TextStyle(color: theme.textTheme.bodySmall?.color),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true) {
      await _deleteConversation(
        context,
        conversation,
        currentUser,
        messageService,
      );
    }
  }

  Future<void> _deleteConversation(
    BuildContext context,
    ConversationModel conversation,
    UserModel currentUser,
    MessageService messageService,
  ) async {
    try {
      final otherUserId = conversation.getOtherUserId(currentUser.id);
      if (otherUserId == null) return;

      await messageService.deleteConversation(
        currentUser.id,
        otherUserId,
        currentUser.id,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa đoạn chat'),
            backgroundColor: Colors.black,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      // Hôm nay - hiển thị giờ
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (difference.inDays == 1) {
      return 'Hôm qua';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }

  Widget _conversationTile({
    BuildContext? context,
    ConversationModel? conversation,
    UserModel? otherUser,
    UserModel? currentUser,
    MessageService? messageService,
    String? nickname,
    String? displayName,
    bool isOnline = false,
    int unreadCount = 0,
    bool isLastMessageFromMe = false,
    String query = '',
    TextStyle? highlightStyle,
    MessageModel? overridePreview,
    GestureTapCallback? onLongPress,
    Widget? child,
  }) {
    if (child != null) {
      return GestureDetector(onLongPress: onLongPress, child: child);
    }
    // các tham số còn lại bắt buộc nếu không truyền child
    final ctx = context!;
    final conv = conversation!;
    final other = otherUser!;
    final current = currentUser!;
    final svc = messageService!;
    final hl =
        highlightStyle ??
        const TextStyle(
          color: Colors.orangeAccent,
          fontWeight: FontWeight.w700,
        );
    final effectiveName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : other.fullName;
    final previewContent =
        overridePreview?.content ??
        conv.lastMessageContent ??
        'Chưa có tin nhắn';

    final theme = Theme.of(context);
    final nameWidget = _buildHighlightedText(
      effectiveName,
      query,
      TextStyle(
        color: unreadCount > 0
            ? theme.colorScheme.onPrimary
            : theme.textTheme.bodyLarge?.color,
        fontSize: 16,
        fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
      ),
      hl,
    );

    final previewWidget = _buildHighlightedText(
      previewContent,
      query,
      TextStyle(
        color: unreadCount > 0
            ? theme.colorScheme.onPrimary
            : theme.textTheme.bodySmall?.color,
        fontSize: 14,
        fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
      ),
      hl,
    );

    final tileChild =
        child ??
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: other.avatarUrl != null
                        ? NetworkImage(other.avatarUrl!)
                        : null,
                    child: other.avatarUrl == null
                        ? Text(
                            effectiveName.isNotEmpty
                                ? effectiveName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                              fontSize: 20,
                            ),
                          )
                        : null,
                  ),
                  // ✅ Chấm xanh trạng thái hoạt động (online) - chỉ hiển thị khi setting được bật
                  if (_activityStatusEnabled && isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF31A24C),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (conversation.isPinned) ...[
                          Icon(
                            Icons.push_pin,
                            size: 14,
                            color: Colors.orange[400],
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(child: nameWidget),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 18,
                          splashRadius: 18,
                          icon: Icon(
                            Icons.more_vert,
                            color: theme.iconTheme.color?.withOpacity(0.6),
                            size: 18,
                          ),
                          onPressed: () => _showConversationOptionsDialog(
                            ctx,
                            conv,
                            other,
                            current,
                            svc,
                          ),
                        ),
                        Text(
                          _formatTime(conv.lastMessageTime),
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (isLastMessageFromMe)
                          const Icon(
                            Icons.done_all,
                            size: 16,
                            color: Colors.blue,
                          ),
                        if (isLastMessageFromMe) const SizedBox(width: 4),
                        Expanded(child: previewWidget),
                        if (unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              unreadCount.toString(),
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
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
        );

    return GestureDetector(
      onLongPress:
          onLongPress ??
          () => _showConversationOptionsDialog(ctx, conv, other, current, svc),
      child: InkWell(
        onTap: () async {
          await svc.markConversationAsRead(conv.id, current.id);

          // Nếu có postIdToShare, gửi message với post link trước
          if (widget.postIdToShare != null) {
            try {
              final postLink = 'https://synap.app/post/${widget.postIdToShare}';
              final shareMessage = MessageModel(
                id: '',
                senderId: current.id,
                receiverId: other.id,
                content: postLink,
                createdAt: DateTime.now(),
              );
              await svc.sendMessage(shareMessage);
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      ErrorMessageHelper.getErrorMessage(
                        e,
                        defaultMessage: 'Không thể gửi bài viết',
                      ),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }

          if (ctx.mounted) {
            Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => ChatScreen(otherUser: other)),
            );
          }
        },
        child: tileChild,
      ),
    );
  }

  Widget _buildHighlightedText(
    String text,
    String query,
    TextStyle baseStyle,
    TextStyle highlightStyle,
  ) {
    if (query.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lower = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final index = lower.indexOf(lowerQuery, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }
      if (index > start) {
        spans.add(
          TextSpan(text: text.substring(start, index), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + lowerQuery.length),
          style: highlightStyle,
        ),
      );
      start = index + lowerQuery.length;
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  Widget _buildGroupConversationTile({
    required BuildContext context,
    required ConversationModel conversation,
    required GroupModel group,
    required UserModel currentUser,
    required MessageService messageService,
    required int unreadCount,
    required bool isLastMessageFromMe,
    required String query,
    required TextStyle highlightStyle,
  }) {
    final groupName = group.name;
    final previewContent =
        conversation.lastMessageContent ?? 'Chưa có tin nhắn';

    final theme = Theme.of(context);
    final nameWidget = _buildHighlightedText(
      groupName,
      query,
      TextStyle(
        color: unreadCount > 0
            ? theme.colorScheme.onPrimary
            : theme.textTheme.bodyLarge?.color,
        fontSize: 16,
        fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
      ),
      highlightStyle,
    );

    final previewWidget = _buildHighlightedText(
      previewContent,
      query,
      TextStyle(
        color: unreadCount > 0
            ? theme.colorScheme.onPrimary
            : theme.textTheme.bodySmall?.color,
        fontSize: 14,
        fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
      ),
      highlightStyle,
    );

    return GestureDetector(
      onLongPress: () {
        if (conversation.type == 'group' && conversation.groupId != null) {
          showModalBottomSheet(
            context: context,
            builder: (context) => Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Thông tin nhóm'),
                    onTap: () {
                      Navigator.pop(context);
                      // Navigate to group info screen
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tính năng đang phát triển')),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_off),
                    title: const Text('Tắt thông báo'),
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tính năng đang phát triển')),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }
      },
      child: InkWell(
        onTap: () async {
          await messageService.markConversationAsRead(
            conversation.id,
            currentUser.id,
          );

          // Nếu có postIdToShare, gửi message với post link vào group trước
          if (widget.postIdToShare != null) {
            try {
              final postLink = 'https://synap.app/post/${widget.postIdToShare}';
              final shareMessage = MessageModel(
                id: '',
                senderId: currentUser.id,
                receiverId: '', // Group message không cần receiverId
                groupId: group.id,
                content: postLink,
                createdAt: DateTime.now(),
              );
              await messageService.sendGroupMessage(shareMessage);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ErrorMessageHelper.getErrorMessage(
                        e,
                        defaultMessage: 'Không thể gửi bài viết',
                      ),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }

          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: group.coverUrl != null
                        ? NetworkImage(group.coverUrl!)
                        : null,
                    child: group.coverUrl == null
                        ? Text(
                            groupName.isNotEmpty
                                ? groupName[0].toUpperCase()
                                : 'G',
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                              fontSize: 20,
                            ),
                          )
                        : null,
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (conversation.isPinned) ...[
                          Icon(
                            Icons.push_pin,
                            size: 14,
                            color: Colors.orange[400],
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(child: nameWidget),
                        Text(
                          _formatTime(conversation.lastMessageTime),
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (isLastMessageFromMe)
                          const Icon(
                            Icons.done_all,
                            size: 16,
                            color: Colors.blue,
                          ),
                        if (isLastMessageFromMe) const SizedBox(width: 4),
                        Expanded(child: previewWidget),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
