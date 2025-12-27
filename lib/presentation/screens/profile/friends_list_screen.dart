import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/user_service.dart';
import '../../providers/auth_provider.dart';

class FriendsListScreen extends StatefulWidget {
  const FriendsListScreen({super.key});

  @override
  State<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  final FriendService _friendService = FriendService();
  final UserService _userService = UserService();
  bool _isLoading = true;
  List<UserModel> _friends = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
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
        title: const Text('Bạn bè'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? const Center(child: Text('Bạn chưa có bạn bè nào'))
              : RefreshIndicator(
                  onRefresh: _loadFriends,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _friends.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final friend = _friends[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: friend.avatarUrl != null
                              ? NetworkImage(friend.avatarUrl!)
                              : null,
                          child: friend.avatarUrl == null
                              ? Text(friend.fullName[0].toUpperCase())
                              : null,
                        ),
                        title: Text(friend.fullName),
                        subtitle: Text('@${friend.username}'),
                      );
                    },
                  ),
                ),
    );
  }
}



