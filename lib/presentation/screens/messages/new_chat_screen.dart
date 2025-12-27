import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/group_model.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/group_service.dart';
import '../../../data/services/message_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/error_message_helper.dart';
import '../../providers/auth_provider.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  final bool isGroupMode;
  final List<String>? preSelectedUserIds;

  const NewChatScreen({
    super.key,
    this.isGroupMode = false,
    this.preSelectedUserIds,
  });

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final FriendService _friendService = FriendService();
  final UserService _userService = UserService();
  final GroupService _groupService = GroupService();
  final MessageService _messageService = MessageService();
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _friends = [];
  List<UserModel> _filteredFriends = [];
  bool _isLoading = true;
  bool _isCreatingGroup = false;
  Set<String> _selectedFriends = {};

  @override
  void initState() {
    super.initState();
    // Nếu có danh sách người dùng đã chọn sẵn, thêm vào _selectedFriends
    if (widget.preSelectedUserIds != null) {
      _selectedFriends = Set<String>.from(widget.preSelectedUserIds!);
    }
    _loadFriends();
    _searchController.addListener(_filterFriends);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    try {
      final friendIds = await _friendService.getFriends(currentUser.id);
      final friends = await Future.wait(
        friendIds.map((id) => _userService.getUserById(id)),
      );

      if (mounted) {
        setState(() {
          _friends = friends.whereType<UserModel>().toList();
          _filteredFriends = _friends;
          _isLoading = false;
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

  void _filterFriends() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredFriends = _friends;
      } else {
        _filteredFriends = _friends.where((friend) {
          return friend.fullName.toLowerCase().contains(query) ||
              friend.username.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _createGroupChat() async {
    // Yêu cầu tối thiểu 2 người bạn (tổng cộng 3 người bao gồm người tạo)
    if (_selectedFriends.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vui lòng chọn ít nhất 2 người bạn để tạo nhóm (tối thiểu 3 người)',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final TextEditingController nameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Tạo nhóm chat',
          style: TextStyle(color: Colors.black),
        ),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            hintText: 'Tên nhóm',
            hintStyle: TextStyle(color: Colors.grey[600]),
            filled: true,
            fillColor: Colors.grey[300]!,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text(
              'Tạo',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );

    if (result != true || nameController.text.trim().isEmpty) return;

    setState(() {
      _isCreatingGroup = true;
    });

    try {
      // Tạo group chat
      final memberIds = [currentUser.id, ..._selectedFriends.toList()];
      final group = GroupModel(
        id: '',
        name: nameController.text.trim(),
        creatorId: currentUser.id,
        memberIds: memberIds,
        type: GroupType.chat, // Nhóm nhắn tin
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final groupId = await _groupService.createGroup(group);

      // Tạo conversation cho group
      await _messageService.getOrCreateGroupConversation(groupId);

      // Lấy group đã tạo
      final createdGroup = await _groupService.getGroup(groupId);

      if (mounted && createdGroup != null) {
        Navigator.of(context).pop(); // Đóng NewChatScreen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupChatScreen(group: createdGroup),
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tạo nhóm chat thành công!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorMessageHelper.getErrorMessage(
                e,
                defaultMessage: 'Không thể tạo nhóm chat',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingGroup = false;
          _selectedFriends.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          widget.isGroupMode
              ? (_selectedFriends.isEmpty
                    ? 'Tạo nhóm chat'
                    : '${_selectedFriends.length} đã chọn')
              : (_selectedFriends.isEmpty
                    ? 'Cuộc trò chuyện mới'
                    : _selectedFriends.length == 1
                    ? 'Bắt đầu trò chuyện'
                    : '${_selectedFriends.length} đã chọn'),
          style: const TextStyle(color: Colors.black),
        ),
        actions: [
          if (widget.isGroupMode && _selectedFriends.length >= 2)
            IconButton(
              icon: const Icon(Icons.group_add, color: Colors.black),
              onPressed: _isCreatingGroup ? null : _createGroupChat,
              tooltip: 'Tạo nhóm',
            ),
        ],
      ),
      body: Column(
        children: [
          // Info banner - chỉ hiển thị khi ở chế độ tạo nhóm
          if (widget.isGroupMode && _selectedFriends.length < 2)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey[300]!,
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chọn ít nhất 2 người bạn để tạo nhóm (tối thiểu 3 người)',
                      style: TextStyle(color: Colors.grey[300], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.black),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm bạn bè...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[300]!,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // Friends list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  )
                : _filteredFriends.isEmpty
                ? Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? 'Chưa có bạn bè nào'
                          : 'Không tìm thấy bạn bè',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredFriends.length,
                    itemBuilder: (context, index) {
                      final friend = _filteredFriends[index];
                      final isSelected = _selectedFriends.contains(friend.id);
                      return ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundImage: friend.avatarUrl != null
                                  ? NetworkImage(friend.avatarUrl!)
                                  : null,
                              child: friend.avatarUrl == null
                                  ? Text(
                                      friend.fullName[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.black,
                                      ),
                                    )
                                  : null,
                            ),
                            if (isSelected)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.black,
                                    size: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          friend.fullName,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '@${friend.username}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        onTap: () {
                          if (widget.isGroupMode) {
                            // Chế độ tạo nhóm: chọn nhiều người
                            setState(() {
                              if (isSelected) {
                                _selectedFriends.remove(friend.id);
                              } else {
                                _selectedFriends.add(friend.id);
                              }
                            });
                          } else {
                            // Chế độ chat 1-1: chọn 1 người và mở chat ngay
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(otherUser: friend),
                              ),
                            );
                          }
                        },
                        onLongPress: () {
                          // Long press để mở chat trực tiếp
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(otherUser: friend),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
