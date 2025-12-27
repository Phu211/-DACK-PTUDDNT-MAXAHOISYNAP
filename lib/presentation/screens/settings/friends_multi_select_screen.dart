import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/user_model.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/user_service.dart';
import '../../providers/auth_provider.dart';

class FriendsMultiSelectScreen extends StatefulWidget {
  final String title;
  final Set<String> initialSelectedIds;

  const FriendsMultiSelectScreen({
    super.key,
    required this.title,
    required this.initialSelectedIds,
  });

  @override
  State<FriendsMultiSelectScreen> createState() =>
      _FriendsMultiSelectScreenState();
}

class _FriendsMultiSelectScreenState extends State<FriendsMultiSelectScreen> {
  final FriendService _friendService = FriendService();
  final UserService _userService = UserService();
  bool _isLoading = true;
  List<UserModel> _friends = [];
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final auth = context.read<AuthProvider>();
    final currentUser = auth.currentUser;
    if (currentUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    try {
      final friendIds = await _friendService.getFriends(currentUser.id);
      final users = await _userService.getUsersByIds(friendIds);
      if (mounted) {
        setState(() {
          _friends = users;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(_selectedIds.toList());
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? const Center(child: Text('Bạn chưa có bạn bè nào'))
              : ListView.builder(
                  itemCount: _friends.length,
                  itemBuilder: (context, index) {
                    final user = _friends[index];
                    final isSelected = _selectedIds.contains(user.id);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedIds.add(user.id);
                          } else {
                            _selectedIds.remove(user.id);
                          }
                        });
                      },
                      title: Text(user.fullName),
                      subtitle: Text('@${user.username}'),
                      secondary: CircleAvatar(
                        backgroundColor: Colors.grey[300],
                        backgroundImage: user.avatarUrl != null
                            ? NetworkImage(user.avatarUrl!)
                            : null,
                        child: user.avatarUrl == null
                            ? Text(user.fullName[0].toUpperCase())
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}


