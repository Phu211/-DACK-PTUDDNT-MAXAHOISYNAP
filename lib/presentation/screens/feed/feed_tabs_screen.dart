import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/post_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/group_service.dart';
import '../../../core/utils/responsive.dart';
import '../../widgets/post_card.dart';
import '../../widgets/stories_section.dart';

enum FeedTab { all, friends, groups }

class FeedTabsScreen extends StatefulWidget {
  const FeedTabsScreen({super.key});

  @override
  State<FeedTabsScreen> createState() => _FeedTabsScreenState();
}

class _FeedTabsScreenState extends State<FeedTabsScreen> {
  FeedTab _selectedTab = FeedTab.all;
  Set<String> _viewedPostIds = {};

  @override
  void initState() {
    super.initState();
    _loadViewedPosts();
  }

  Future<void> _loadViewedPosts() async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id;
    if (userId != null) {
      final firestoreService = FirestoreService();
      final viewedIds = await firestoreService.getViewedPostIds(userId);
      if (mounted) {
        setState(() {
          _viewedPostIds = viewedIds;
        });
      }
    }
  }

  Future<void> _markPostAsViewed(String postId) async {
    if (_viewedPostIds.contains(postId)) return;

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id;
    if (userId != null) {
      final firestoreService = FirestoreService();
      await firestoreService.markPostAsViewed(postId, userId);
      if (mounted) {
        setState(() {
          _viewedPostIds.add(postId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final firestoreService = FirestoreService();

    if (!authProvider.isAuthenticated) {
      return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập')));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Bảng feed'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Feed Tabs
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE4E6EB), width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    'Tất cả',
                    FeedTab.all,
                    _selectedTab == FeedTab.all,
                  ),
                ),
                Expanded(
                  child: _buildTabButton(
                    'Bạn bè',
                    FeedTab.friends,
                    _selectedTab == FeedTab.friends,
                  ),
                ),
                Expanded(
                  child: _buildTabButton(
                    'Nhóm',
                    FeedTab.groups,
                    _selectedTab == FeedTab.groups,
                  ),
                ),
              ],
            ),
          ),

          // Feed Content
          Expanded(
            child: StreamBuilder<List<PostModel>>(
              stream: firestoreService.getPostsStream(
                currentUserId: authProvider.currentUser?.id,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Lỗi: ${snapshot.error}',
                      style: const TextStyle(color: Colors.black87),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return SingleChildScrollView(
                    padding: Responsive.responsivePadding(context),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: Responsive.maxContentWidth(context),
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            const StoriesSection(),
                            const SizedBox(height: 16),
                            Text(
                              _getEmptyMessage(),
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final allPosts = snapshot.data!;
                return _buildFilteredFeed(
                  context,
                  allPosts,
                  authProvider.currentUser?.id,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, FeedTab tab, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab = tab;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.black : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildFilteredFeed(
    BuildContext context,
    List<PostModel> allPosts,
    String? currentUserId,
  ) {
    if (currentUserId == null) {
      return const Center(child: Text('Vui lòng đăng nhập'));
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _getFilterData(currentUserId),
      builder: (context, filterSnapshot) {
        if (filterSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.black),
          );
        }

        final friendIds =
            filterSnapshot.data?['friendIds'] as Set<String>? ?? {};
        final groupIds = filterSnapshot.data?['groupIds'] as Set<String>? ?? {};

        // Filter posts based on selected tab
        List<PostModel> filteredPosts;
        switch (_selectedTab) {
          case FeedTab.friends:
            filteredPosts = allPosts.where((post) {
              // Exclude own posts and group posts
              if (post.userId == currentUserId) return false;
              if (post.groupId != null && post.groupId!.isNotEmpty) return false;
              return friendIds.contains(post.userId);
            }).toList();
            break;
          case FeedTab.groups:
            filteredPosts = allPosts.where((post) {
              // Only show posts that belong to groups the user is a member of
              return post.groupId != null && 
                     post.groupId!.isNotEmpty && 
                     groupIds.contains(post.groupId);
            }).toList();
            break;
          case FeedTab.all:
            filteredPosts = allPosts.where((post) {
              // Include own posts, friend posts, and group posts
              if (post.userId == currentUserId) return true;
              if (post.groupId != null && 
                  post.groupId!.isNotEmpty && 
                  groupIds.contains(post.groupId)) return true;
              return friendIds.contains(post.userId);
            }).toList();
            break;
        }

        // Check if all posts are viewed
        final allPostsViewed =
            filteredPosts.isNotEmpty &&
            filteredPosts.every((post) => _viewedPostIds.contains(post.id));

        // Mark posts as viewed when displayed
        for (final post in filteredPosts) {
          _markPostAsViewed(post.id);
        }

        if (filteredPosts.isEmpty) {
          return SingleChildScrollView(
            padding: Responsive.responsivePadding(context),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Responsive.maxContentWidth(context),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    const StoriesSection(),
                    const SizedBox(height: 16),
                    Text(
                      _getEmptyMessage(),
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await _loadViewedPosts();
          },
          backgroundColor: Colors.white,
          color: Colors.black,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.maxContentWidth(context),
              ),
              child: ListView.builder(
                padding: Responsive.responsivePadding(
                  context,
                ).copyWith(top: 12, bottom: 12),
                itemCount: filteredPosts.length + 1 + (allPostsViewed ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Stories section
                    return const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: StoriesSection(),
                    );
                  }

                  // "All viewed" message
                  if (allPostsViewed && index == filteredPosts.length + 1) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 16,
                      ),
                      child: Center(
                        child: Text(
                          'Bạn đã xem hết bài viết',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  }

                  final post = filteredPosts[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PostCard(post: post),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _getFilterData(String currentUserId) async {
    final friendService = FriendService();
    final groupService = GroupService();

    final friendIds = await friendService.getFriends(currentUserId);
    final userGroups = await groupService.getUserGroups(currentUserId).first;
    final groupIds = userGroups.map((g) => g.id).toSet();

    return {'friendIds': friendIds.toSet(), 'groupIds': groupIds};
  }

  String _getEmptyMessage() {
    switch (_selectedTab) {
      case FeedTab.friends:
        return 'Chưa có bài viết từ bạn bè.';
      case FeedTab.groups:
        return 'Chưa có bài viết từ nhóm.';
      case FeedTab.all:
        return 'Chưa có bài viết nào. Hãy là người đầu tiên đăng bài!';
    }
  }
}
