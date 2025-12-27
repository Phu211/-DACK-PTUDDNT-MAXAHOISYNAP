import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/feed_control_service.dart';
import '../../../data/services/user_service.dart';
import '../../providers/auth_provider.dart';
import '../../../core/utils/error_message_helper.dart';
import '../../widgets/post_card.dart';

class HiddenContentScreen extends StatefulWidget {
  const HiddenContentScreen({super.key});

  @override
  State<HiddenContentScreen> createState() => _HiddenContentScreenState();
}

class _HiddenContentScreenState extends State<HiddenContentScreen> with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final FeedControlService _feedControlService = FeedControlService();
  final UserService _userService = UserService();

  late TabController _tabController;
  bool _isLoading = true;
  
  // Hidden posts
  List<Map<String, dynamic>> _hiddenPosts = [];
  Map<String, dynamic> _postData = {}; // postId -> PostModel data
  
  // Temporarily hidden users (30 days)
  List<Map<String, dynamic>> _temporarilyHiddenUsers = [];
  Map<String, dynamic> _userData = {}; // userId -> UserModel data
  
  // Permanently hidden users (unfollowed)
  List<Map<String, dynamic>> _unfollowedUsers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Load hidden posts
      final hiddenPosts = await _firestoreService.getHiddenPosts(currentUser.id);
      _hiddenPosts = hiddenPosts;
      
      // Load post data for hidden posts
      for (final item in hiddenPosts) {
        final postId = item['postId'] as String;
        try {
          final post = await _firestoreService.getPost(postId, viewerId: currentUser.id);
          if (post != null) {
            _postData[postId] = post;
          }
        } catch (e) {
          // Post might be deleted, skip
        }
      }

      // Load temporarily hidden users
      final tempHiddenUsers = await _firestoreService.getTemporarilyHiddenUsers(currentUser.id);
      _temporarilyHiddenUsers = tempHiddenUsers;
      
      // Load user data for temporarily hidden users
      for (final item in tempHiddenUsers) {
        final userId = item['hiddenUserId'] as String;
        try {
          final user = await _userService.getUserById(userId);
          if (user != null) {
            _userData[userId] = user;
          }
        } catch (e) {
          // User might be deleted, skip
        }
      }

      // Load permanently hidden users (unfollowed)
      final unfollowedUsers = await _feedControlService.getUnfollowedUsers(currentUser.id);
      _unfollowedUsers = unfollowedUsers;
      
      // Load user data for unfollowed users
      for (final item in unfollowedUsers) {
        final userId = item['hiddenUserId'] as String;
        if (!_userData.containsKey(userId)) {
          try {
            final user = await _userService.getUserById(userId);
            if (user != null) {
              _userData[userId] = user;
            }
          } catch (e) {
            // User might be deleted, skip
          }
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(e),
        );
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _unhidePost(String postId) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      await _firestoreService.unhidePost(postId, currentUser.id);
      
      setState(() {
        _hiddenPosts.removeWhere((item) => item['postId'] == postId);
        _postData.remove(postId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã bỏ ẩn bài viết'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(e),
        );
      }
    }
  }

  Future<void> _unhideTemporarilyHiddenUser(String userId) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      await _firestoreService.unhideUser(currentUser.id, userId);
      
      setState(() {
        _temporarilyHiddenUsers.removeWhere((item) => item['hiddenUserId'] == userId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã bỏ ẩn người dùng'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(e),
        );
      }
    }
  }

  Future<void> _unfollowUser(String userId) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      await _feedControlService.followUser(currentUser.id, userId);
      
      setState(() {
        _unfollowedUsers.removeWhere((item) => item['hiddenUserId'] == userId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã bỏ ẩn người dùng'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(e),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách bài viết và người dùng bị ẩn'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Bài viết'),
            Tab(text: 'Tạm ẩn (30 ngày)'),
            Tab(text: 'Ẩn vĩnh viễn'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildHiddenPostsTab(),
                _buildTemporarilyHiddenUsersTab(),
                _buildUnfollowedUsersTab(),
              ],
            ),
    );
  }

  Widget _buildHiddenPostsTab() {
    if (_hiddenPosts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Chưa có bài viết nào bị ẩn',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        itemCount: _hiddenPosts.length,
        itemBuilder: (context, index) {
          final item = _hiddenPosts[index];
          final postId = item['postId'] as String;
          final post = _postData[postId];

          if (post == null) {
            // Post might be deleted
            return ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.grey),
              title: const Text('Bài viết đã bị xóa'),
              subtitle: Text('ID: $postId'),
              trailing: TextButton(
                onPressed: () => _unhidePost(postId),
                child: const Text('Bỏ ẩn'),
              ),
            );
          }

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Post content
                PostCard(post: post),
                // Unhide button
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.visibility),
                      label: const Text('Bỏ ẩn bài viết'),
                      onPressed: () => _unhidePost(postId),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTemporarilyHiddenUsersTab() {
    if (_temporarilyHiddenUsers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Chưa có người dùng nào bị tạm ẩn',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        itemCount: _temporarilyHiddenUsers.length,
        itemBuilder: (context, index) {
          final item = _temporarilyHiddenUsers[index];
          final userId = item['hiddenUserId'] as String;
          final hideUntil = item['hideUntil'] as DateTime?;
          final user = _userData[userId];

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: user?.profileImageUrl != null
                    ? NetworkImage(user!.profileImageUrl!)
                    : null,
                child: user?.profileImageUrl == null
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Text(
                user?.fullName ?? 'Người dùng',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: hideUntil != null
                  ? Text('Tạm ẩn đến: ${_formatDate(hideUntil)}')
                  : const Text('Tạm ẩn trong 30 ngày'),
              trailing: OutlinedButton(
                onPressed: () => _unhideTemporarilyHiddenUser(userId),
                child: const Text('Bỏ ẩn'),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUnfollowedUsersTab() {
    if (_unfollowedUsers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Chưa có người dùng nào bị ẩn vĩnh viễn',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        itemCount: _unfollowedUsers.length,
        itemBuilder: (context, index) {
          final item = _unfollowedUsers[index];
          final userId = item['hiddenUserId'] as String;
          final user = _userData[userId];

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: user?.profileImageUrl != null
                    ? NetworkImage(user!.profileImageUrl!)
                    : null,
                child: user?.profileImageUrl == null
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Text(
                user?.fullName ?? 'Người dùng',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Đã ẩn tất cả bài viết'),
              trailing: OutlinedButton(
                onPressed: () => _unfollowUser(userId),
                child: const Text('Bỏ ẩn'),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

