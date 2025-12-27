import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../../providers/auth_provider.dart';
import '../../../data/models/post_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/group_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../core/utils/responsive.dart';
import '../auth/login_screen.dart';
import '../../widgets/post_card.dart';
import '../../widgets/stories_section.dart';
import '../../widgets/home_left_sidebar.dart';
import '../../widgets/home_right_sidebar.dart';
import '../../widgets/home_top_nav_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Set<String> _viewedPostIds = {};
  final FirestoreService _firestoreService = FirestoreService();
  final FriendService _friendService = FriendService();
  final GroupService _groupService = GroupService();
  final AuthService _authService = AuthService();

  bool _emailVerified = true;

  @override
  void initState() {
    super.initState();
    _loadViewedPosts();
    _checkEmailVerified();
  }

  Future<void> _checkEmailVerified() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await user.reload();
      final refreshed = fb_auth.FirebaseAuth.instance.currentUser;
      if (mounted) {
        setState(() {
          _emailVerified = refreshed?.emailVerified ?? true;
        });
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _resendVerificationEmail() async {
    try {
      await _authService.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã gửi email xác thực. Vui lòng kiểm tra hộp thư.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể gửi email xác thực: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadViewedPosts() async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id;
    if (userId != null) {
      final viewedIds = await _firestoreService.getViewedPostIds(userId);
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
      await _firestoreService.markPostAsViewed(postId, userId);
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

    if (!authProvider.isAuthenticated) {
      return const LoginScreen();
    }

    final isDesktop = Responsive.isDesktop(context);
    final isMobile = Responsive.isMobile(context);

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Sidebar (desktop only)
                if (isDesktop)
                  SizedBox(
                    width: Responsive.responsive(
                      context,
                      mobile: 0,
                      tablet: 0,
                      desktop: 260.0,
                    ),
                    child: const HomeLeftSidebar(),
                  ),

                // Middle Column (Feed)
                Expanded(
                  child: Column(
                    children: [
                      // Top Navigation Bar (Mobile only)
                      if (isMobile)
                        HomeTopNavBar(
                          selectedIndex: 0,
                          onItemSelected: (index) {
                            // Navigation is handled by MainScreen
                          },
                        ),

                      // Email verification banner
                      if (!_emailVerified)
                        Builder(
                          builder: (context) {
                            final theme = Theme.of(context);
                            return Container(
                              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange[200]!),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Email của bạn chưa được xác thực',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: theme
                                                .textTheme
                                                .bodyLarge
                                                ?.color,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Vui lòng kiểm tra hộp thư để xác thực email. ',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme
                                                .textTheme
                                                .bodySmall
                                                ?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: _resendVerificationEmail,
                                    child: const Text('GỬI LẠI'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      // Feed Content
                      Expanded(
                        child: StreamBuilder<List<PostModel>>(
                          stream: _firestoreService.getPostsStream(
                            currentUserId: authProvider.currentUser?.id,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Center(
                                child: CircularProgressIndicator(
                                  color: Theme.of(context).primaryColor,
                                ),
                              );
                            }

                            if (snapshot.hasError) {
                              if (kDebugMode) {
                                print(
                                  'ERROR in HomeScreen StreamBuilder: ${snapshot.error}',
                                );
                                print(
                                  'Error details: ${snapshot.error.toString()}',
                                );
                              }
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 48,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Lỗi tải dữ liệu: ${snapshot.error}',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {});
                                      },
                                      child: const Text('Thử lại'),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return SingleChildScrollView(
                                padding: Responsive.responsivePadding(context),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: Responsive.maxContentWidth(
                                        context,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        const SizedBox(height: 12),
                                        const StoriesSection(),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Chưa có bài viết nào. Hãy là người đầu tiên đăng bài!',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).textTheme.bodyLarge?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }

                            final allPosts = snapshot.data!;
                            return _buildFeed(context, allPosts, isMobile);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Right Sidebar (desktop only)
                if (isDesktop)
                  SizedBox(width: 350.0, child: const HomeRightSidebar()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeed(
    BuildContext context,
    List<PostModel> allPosts,
    bool isMobile,
  ) {
    if (allPosts.isEmpty) {
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
                  'Chưa có bài viết nào. Hãy là người đầu tiên đăng bài!',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Check if all posts are viewed
    final allPostsViewed =
        allPosts.isNotEmpty &&
        allPosts.every((post) => _viewedPostIds.contains(post.id));

    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        await _loadViewedPosts();
        await _checkEmailVerified();
      },
      backgroundColor: theme.scaffoldBackgroundColor,
      color: theme.primaryColor,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.maxContentWidth(context),
          ),
          child: ListView.builder(
            padding: Responsive.responsivePadding(
              context,
            ).copyWith(top: 12, bottom: isMobile ? 80 : 12),
            itemCount: allPosts.length + 1 + (allPostsViewed ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == 0) {
                // Stories section
                return const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: StoriesSection(),
                );
              }

              // "All viewed" message
              if (allPostsViewed && index == allPosts.length + 1) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  child: Center(
                    child: Text(
                      'Bạn đã xem hết bài viết',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ),
                );
              }

              final post = allPosts[index - 1];
              // Mark as viewed when the item is built (avoid doing work in parent build).
              _markPostAsViewed(post.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PostCard(post: post),
              );
            },
          ),
        ),
      ),
    );
  }
}
