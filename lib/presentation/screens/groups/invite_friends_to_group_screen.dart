import 'package:flutter/material.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/group_model.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/group_service.dart';
import '../../../core/utils/error_message_helper.dart';

class InviteFriendsToGroupScreen extends StatefulWidget {
  final GroupModel group;
  final String currentUserId;

  const InviteFriendsToGroupScreen({
    super.key,
    required this.group,
    required this.currentUserId,
  });

  @override
  State<InviteFriendsToGroupScreen> createState() => _InviteFriendsToGroupScreenState();
}

class _InviteFriendsToGroupScreenState extends State<InviteFriendsToGroupScreen> {
  final FriendService _friendService = FriendService();
  final UserService _userService = UserService();
  final GroupService _groupService = GroupService();
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _friends = [];
  List<UserModel> _filteredFriends = [];
  Set<String> _selectedFriends = {};
  bool _isLoading = true;
  bool _isInviting = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _searchController.addListener(_filterFriends);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final friendIds = await _friendService.getFriends(widget.currentUserId);

      // Lọc ra những bạn bè chưa có trong nhóm
      final existingMemberIds = widget.group.memberIds.toSet();
      final friendIdsNotInGroup = friendIds
          .where((id) => !existingMemberIds.contains(id))
          .toList();

      final friends = await Future.wait(
        friendIdsNotInGroup.map((id) => _userService.getUserById(id)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(e),
        );
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

  Future<void> _inviteFriends() async {
    if (_selectedFriends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn ít nhất một người bạn'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isInviting = true;
    });

    try {
      int successCount = 0;
      int failCount = 0;

      for (final friendId in _selectedFriends) {
        try {
          await _groupService.addMember(
            widget.group.id,
            widget.currentUserId,
            friendId,
          );
          successCount++;
        } catch (e) {
          failCount++;
          debugPrint('Error inviting member $friendId: $e');
        }
      }

      if (mounted) {
        setState(() {
          _isInviting = false;
        });

        if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                failCount > 0
                    ? 'Đã mời $successCount người. $failCount người không thể mời.'
                    : 'Đã mời $successCount người vào nhóm thành công!',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true); // Return true to refresh
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Không thể mời bạn bè: ${failCount > 0 ? "Đã có lỗi xảy ra" : "Vui lòng thử lại"}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInviting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(e),
        );
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
          _selectedFriends.isEmpty
              ? 'Mời bạn bè'
              : '${_selectedFriends.length} đã chọn',
          style: const TextStyle(color: Colors.black),
        ),
        actions: [
          if (_selectedFriends.isNotEmpty)
            TextButton(
              onPressed: _isInviting ? null : _inviteFriends,
              child: _isInviting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Mời',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
            ),
        ],
      ),
      body: Column(
        children: [
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
                              ? 'Không có bạn bè nào để mời'
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
                                          friend.fullName.isNotEmpty
                                              ? friend.fullName[0].toUpperCase()
                                              : 'U',
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
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              friend.fullName,
                              style: TextStyle(
                                color: isSelected ? Colors.blue : Colors.black,
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
                              setState(() {
                                if (isSelected) {
                                  _selectedFriends.remove(friend.id);
                                } else {
                                  _selectedFriends.add(friend.id);
                                }
                              });
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

