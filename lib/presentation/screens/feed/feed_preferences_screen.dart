import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/feed_control_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';

class FeedPreferencesScreen extends StatefulWidget {
  const FeedPreferencesScreen({super.key});

  @override
  State<FeedPreferencesScreen> createState() => _FeedPreferencesScreenState();
}

class _FeedPreferencesScreenState extends State<FeedPreferencesScreen> {
  final FeedControlService _feedControlService = FeedControlService();
  final UserService _userService = UserService();
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  List<String> _unfollowedUserIds = [];
  List<UserModel> _unfollowedUsers = [];
  List<Map<String, dynamic>> _temporarilyHiddenUsers = [];
  Map<String, UserModel> _hiddenUsersMap = {};

  @override
  void initState() {
    super.initState();
    _loadFeedPreferences();
  }

  Future<void> _loadFeedPreferences() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      // Load unfollowed users
      final preferences = await _feedControlService.getFeedPreferences(currentUser.id);
      _unfollowedUserIds = List<String>.from(preferences['unfollowedUserIds'] ?? []);

      final unfollowedUsers = <UserModel>[];
      for (final userId in _unfollowedUserIds) {
        try {
          final user = await _userService.getUserById(userId);
          if (user != null) {
            unfollowedUsers.add(user);
          }
        } catch (e) {
          // Skip if user not found
        }
      }

      // Load temporarily hidden users
      _temporarilyHiddenUsers = await _firestoreService.getTemporarilyHiddenUsers(currentUser.id);
      final hiddenUsersMap = <String, UserModel>{};
      
      for (final hiddenData in _temporarilyHiddenUsers) {
        final hiddenUserId = hiddenData['hiddenUserId'] as String;
        try {
          final user = await _userService.getUserById(hiddenUserId);
          if (user != null) {
            hiddenUsersMap[hiddenUserId] = user;
          }
        } catch (e) {
          // Skip if user not found
        }
      }

      setState(() {
        _unfollowedUsers = unfollowedUsers;
        _hiddenUsersMap = hiddenUsersMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  Future<void> _followUserAgain(String userId) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      await _feedControlService.followUser(currentUser.id, userId);
      await _loadFeedPreferences();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã bỏ ẩn người dùng')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  Future<void> _unhideTemporarilyHiddenUser(String hiddenUserId) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      await _firestoreService.unhideUser(currentUser.id, hiddenUserId);
      await _loadFeedPreferences();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã bỏ ẩn người dùng')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  String _formatRemainingDays(DateTime hideUntil) {
    final now = DateTime.now();
    final difference = hideUntil.difference(now);
    final days = difference.inDays;
    if (days <= 0) {
      return 'Đã hết hạn';
    } else if (days == 1) {
      return 'Còn 1 ngày';
    } else {
      return 'Còn $days ngày';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Bảng feed'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Tùy chỉnh Bảng feed của bạn để xem nội dung bạn quan tâm nhất.',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),

                  // Temporarily hidden users section
                  if (_temporarilyHiddenUsers.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'Tạm ẩn trong 30 ngày',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _temporarilyHiddenUsers.length,
                      itemBuilder: (context, index) {
                        final hiddenData = _temporarilyHiddenUsers[index];
                        final hiddenUserId = hiddenData['hiddenUserId'] as String;
                        final hideUntil = hiddenData['hideUntil'] as DateTime;
                        final user = _hiddenUsersMap[hiddenUserId];
                        
                        if (user == null) return const SizedBox.shrink();
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[300],
                            backgroundImage: user.avatarUrl != null
                                ? NetworkImage(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(user.fullName[0].toUpperCase())
                                : null,
                          ),
                          title: Text(user.fullName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('@${user.username}'),
                              const SizedBox(height: 4),
                              Text(
                                _formatRemainingDays(hideUntil),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          trailing: TextButton(
                            onPressed: () => _unhideTemporarilyHiddenUser(hiddenUserId),
                            child: const Text('Bỏ ẩn'),
                          ),
                        );
                      },
                    ),
                    const Divider(),
                  ],

                  // Unfollowed users section
                  if (_unfollowedUsers.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'Đã ẩn tất cả bài viết từ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _unfollowedUsers.length,
                      itemBuilder: (context, index) {
                        final user = _unfollowedUsers[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[300],
                            backgroundImage: user.avatarUrl != null
                                ? NetworkImage(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(user.fullName[0].toUpperCase())
                                : null,
                          ),
                          title: Text(user.fullName),
                          subtitle: Text('@${user.username}'),
                          trailing: TextButton(
                            onPressed: () => _followUserAgain(user.id),
                            child: const Text('Bỏ ẩn'),
                          ),
                        );
                      },
                    ),
                    const Divider(),
                  ],

                  // Info section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Các tính năng khác',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoItem(
                          icon: Icons.priority_high,
                          title: 'Ưu tiên người bạn muốn xem trước',
                          description: 'Chọn người bạn muốn xem bài viết của họ trước tiên trong Bảng feed.',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoItem(
                          icon: Icons.tune,
                          title: 'Điều chỉnh sở thích nội dung',
                          description: 'Hệ thống sẽ học từ các bài viết bạn quan tâm và không quan tâm để cải thiện gợi ý.',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoItem(
                          icon: Icons.people_outline,
                          title: 'Quản lý Trang đã thích',
                          description: 'Xem và quản lý các Trang bạn đã thích để điều chỉnh nội dung hiển thị.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: Colors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


