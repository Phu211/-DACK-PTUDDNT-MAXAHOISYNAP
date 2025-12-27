import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/post_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../core/utils/responsive.dart';
import '../../widgets/post_card.dart';
import '../../widgets/stories_section.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
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
      return Scaffold(
        appBar: AppBar(title: const Text('Thước phim')),
        body: const Center(child: Text('Vui lòng đăng nhập')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Thước phim'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<List<PostModel>>(
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
                  child: const Column(
                    children: [
                      SizedBox(height: 12),
                      StoriesSection(),
                      SizedBox(height: 16),
                      Text(
                        'Chưa có video nào.',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final allPosts = snapshot.data!;
          // Filter only posts with video
          final videoPosts = allPosts
              .where(
                (post) => post.videoUrl != null && post.videoUrl!.isNotEmpty,
              )
              .toList();

          // Check if all posts are viewed
          final allPostsViewed =
              videoPosts.isNotEmpty &&
              videoPosts.every((post) => _viewedPostIds.contains(post.id));

          // Mark posts as viewed when displayed
          for (final post in videoPosts) {
            _markPostAsViewed(post.id);
          }

          if (videoPosts.isEmpty) {
            return SingleChildScrollView(
              padding: Responsive.responsivePadding(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.maxContentWidth(context),
                  ),
                  child: const Column(
                    children: [
                      SizedBox(height: 12),
                      StoriesSection(),
                      SizedBox(height: 16),
                      Text(
                        'Chưa có video nào.',
                        style: TextStyle(color: Colors.black87),
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
                  itemCount: videoPosts.length + 1 + (allPostsViewed ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // Stories section
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: StoriesSection(),
                      );
                    }

                    // "All viewed" message
                    if (allPostsViewed && index == videoPosts.length + 1) {
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

                    final post = videoPosts[index - 1];
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
      ),
    );
  }
}
