import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/recommendation_service.dart';
import '../../../data/services/settings_service.dart';
import '../../providers/auth_provider.dart';
import '../profile/other_user_profile_screen.dart';

class PeopleYouMayKnowScreen extends StatefulWidget {
  const PeopleYouMayKnowScreen({super.key});

  @override
  State<PeopleYouMayKnowScreen> createState() => _PeopleYouMayKnowScreenState();
}

class _PeopleYouMayKnowScreenState extends State<PeopleYouMayKnowScreen> {
  bool _suggestFriendsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestFriendsSetting();
  }

  Future<void> _loadSuggestFriendsSetting() async {
    final enabled = await SettingsService.isSuggestFriendsEnabled();
    if (mounted) {
      setState(() {
        _suggestFriendsEnabled = enabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final recommendationService = RecommendationService();

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Vui lòng đăng nhập')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Gợi ý bạn bè',
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: _suggestFriendsEnabled
          ? FutureBuilder<List<UserModel>>(
              future: recommendationService.recommendFriends(currentUser.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.black),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text(
                      'Không có gợi ý bạn bè',
                      style: TextStyle(color: Colors.black87),
                    ),
                  );
                }

                final suggestions = snapshot.data!;

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final user = suggestions[index];
                    return _PeopleSuggestionItem(user: user);
                  },
                );
              },
            )
          : const Center(
              child: Text(
                'Tính năng gợi ý kết bạn đã được tắt trong cài đặt',
                style: TextStyle(color: Colors.black87),
              ),
            ),
    );
  }
}

class _PeopleSuggestionItem extends StatelessWidget {
  final UserModel user;

  const _PeopleSuggestionItem({required this.user});

  Future<int> _getMutualFriendsCount(BuildContext context, String userId) async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return 0;
    
    final recommendationService = RecommendationService();
    
    try {
      final mutualFriends = await recommendationService.getMutualFriends(
        currentUser.id,
        userId,
      );
      return mutualFriends.length;
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendService = FriendService();
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OtherUserProfileScreen(user: user),
                ),
              );
            },
            child: CircleAvatar(
              radius: 30,
              backgroundImage: user.avatarUrl != null
                  ? NetworkImage(user.avatarUrl!)
                  : null,
              child: user.avatarUrl == null
                  ? Text(user.fullName[0].toUpperCase())
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OtherUserProfileScreen(user: user),
                      ),
                    );
                  },
                  child: Text(
                    user.fullName,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FutureBuilder<int>(
                  future: _getMutualFriendsCount(context, user.id),
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    return Text(
                      count > 0 ? '$count bạn chung' : '',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          if (currentUser != null)
            ElevatedButton(
              onPressed: () async {
                try {
                  await friendService.sendFriendRequest(currentUser.id, user.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã gửi lời mời kết bạn'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lỗi: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Thêm bạn bè'),
            ),
        ],
      ),
    );
  }
}


