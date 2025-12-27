import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/friend_request_model.dart';
import 'friend_requests_grid_screen.dart';
import 'people_you_may_know_screen.dart';
import '../profile/other_user_profile_screen.dart';

class FriendsTabsScreen extends StatefulWidget {
  final int initialTabIndex;

  const FriendsTabsScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<FriendsTabsScreen> createState() => _FriendsTabsScreenState();
}

class _FriendsTabsScreenState extends State<FriendsTabsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FriendService _friendService = FriendService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Vui lòng đăng nhập')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Bạn bè',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              child: StreamBuilder<List<FriendRequestModel>>(
                stream: _friendService.getFriendRequests(currentUser.id),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Flexible(
                        child: Text(
                          'Lời mời',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            const Tab(text: 'Gợi ý'),
            const Tab(text: 'Bạn bè'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Lời mời kết bạn
          const FriendRequestsGridScreen(),
          // Tab 2: Gợi ý bạn bè
          const PeopleYouMayKnowScreen(),
          // Tab 3: Bạn bè của bạn
          _MyFriendsTab(currentUserId: currentUser.id),
        ],
      ),
    );
  }
}

class _MyFriendsTab extends StatefulWidget {
  final String currentUserId;

  const _MyFriendsTab({required this.currentUserId});

  @override
  State<_MyFriendsTab> createState() => _MyFriendsTabState();
}

class _MyFriendsTabState extends State<_MyFriendsTab> {
  final FriendService _friendService = FriendService();
  final UserService _userService = UserService();
  List<UserModel> _friends = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Clear cache trước khi load để đảm bảo lấy dữ liệu mới nhất
      final friendIds = await _friendService.getFriends(widget.currentUserId);
      
      // Debug log
      print('FriendService: Loaded ${friendIds.length} friend IDs for user ${widget.currentUserId}');
      print('FriendService: Friend IDs: $friendIds');
      
      if (friendIds.isEmpty) {
        setState(() {
          _friends = [];
          _isLoading = false;
        });
        return;
      }

      final users = await _userService.getUsersByIds(friendIds);
      // Lọc bỏ tài khoản của chính mình
      final filteredUsers = users.where((user) => user.id != widget.currentUserId).toList();
      
      // Debug log
      print('FriendService: Loaded ${filteredUsers.length} users after filtering');
      
      if (mounted) {
        setState(() {
          _friends = filteredUsers;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('FriendService: Error loading friends: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Lỗi: $_error',
              style: const TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFriends,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }

    if (_friends.isEmpty) {
      return const Center(
        child: Text(
          'Bạn chưa có bạn bè nào',
          style: TextStyle(color: Colors.black87),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFriends,
      color: Colors.black,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _friends.length,
        itemBuilder: (context, index) {
          final friend = _friends[index];
          return _FriendListItem(friend: friend);
        },
      ),
    );
  }
}

class _FriendListItem extends StatelessWidget {
  final UserModel friend;

  const _FriendListItem({required this.friend});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OtherUserProfileScreen(user: friend),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage: friend.avatarUrl != null
                  ? NetworkImage(friend.avatarUrl!)
                  : null,
              backgroundColor: Colors.grey[800],
              child: friend.avatarUrl == null
                  ? Text(
                      friend.fullName.isNotEmpty
                          ? friend.fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.fullName,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (friend.username.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '@${friend.username}',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }
}


