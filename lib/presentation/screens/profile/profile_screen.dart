import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../flutter_gen/gen_l10n/app_localizations.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/user_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/post_card.dart';
import '../../widgets/profile_highlights_widget.dart';
import '../../widgets/profile_info_cards_widget.dart';
import '../../widgets/profile_badges_widget.dart';
import '../../widgets/profile_social_links_widget.dart';
import '../../../data/services/profile_view_service.dart';
import 'edit_profile_screen.dart';
import 'friends_list_screen.dart';
import 'other_user_profile_screen.dart';
import 'tagged_posts_screen.dart';
import 'activity_log_screen.dart';
import 'profile_views_list_screen.dart';
import 'blocked_users_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Chưa đăng nhập')));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        title: Text(
          AppLocalizations.of(context)?.profileTitle ?? 'Trang cá nhân',
          style: TextStyle(color: theme.textTheme.titleLarge?.color),
        ),
        actions: [
          // Profile Views icon - luôn hiển thị
          FutureBuilder<int>(
            future: ProfileViewService().getProfileViewsCount(user.id, days: 7),
            builder: (context, snapshot) {
              final viewsCount = snapshot.data ?? 0;
              return IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.visibility, color: theme.iconTheme.color),
                    if (viewsCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: theme.primaryColor, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            viewsCount > 99 ? '99+' : viewsCount.toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => ProfileViewsListScreen(userId: user.id)));
                },
                tooltip: viewsCount > 0 ? '$viewsCount lượt xem profile' : 'Xem lượt xem profile',
              );
            },
          ),
          // Settings icon
          IconButton(
            icon: Icon(Icons.settings, color: theme.iconTheme.color),
            onPressed: () => _showProfileSettings(context, theme, user),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Cover photo with avatar overlay
          SliverToBoxAdapter(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Cover photo
                Container(
                  height: 200,
                  width: double.infinity,
                  color: theme.cardColor,
                  child: user.coverUrl != null
                      ? Image.network(
                          user.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(color: theme.cardColor);
                          },
                        )
                      : null,
                ),
                // Avatar positioned to overlap cover photo
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -50,
                  child: Center(
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: theme.scaffoldBackgroundColor,
                      child: CircleAvatar(
                        radius: 48,
                        backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                        child: user.avatarUrl == null
                            ? Text(
                                user.fullName[0].toUpperCase(),
                                style: TextStyle(fontSize: 40, color: theme.textTheme.bodyLarge?.color),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Profile info below avatar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  // Name
                  Text(
                    user.fullName,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                  ),
                  if (user.bio != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      user.bio!,
                      style: TextStyle(color: theme.textTheme.bodySmall?.color),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Badges
                  ProfileBadgesWidget(userId: user.id),
                  const SizedBox(height: 16),
                  // Stats - Use StreamBuilder to get actual post count (including tagged posts)
                  StreamBuilder<List<PostModel>>(
                    stream: FirestoreService().getAllPostsForUser(
                      user.id,
                      viewerId: user.id, // Owner xem được tất cả posts của mình
                    ),
                    builder: (context, postsSnapshot) {
                      // Get actual post count from stream
                      final actualPostsCount = postsSnapshot.hasData ? postsSnapshot.data!.length : user.postsCount;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatItem(label: 'Bài viết', value: actualPostsCount.toString()),
                          _StatItem(label: 'Người theo dõi', value: user.followersCount.toString()),
                          _StatItem(label: 'Đang theo dõi', value: user.followingCount.toString()),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  // Info Cards
                  ProfileInfoCardsWidget(user: user),
                  const SizedBox(height: 16),
                  // Friends preview section
                  FriendsPreviewSection(currentUserId: user.id),
                  const SizedBox(height: 16),
                  // Highlights section (moved below friends, above posts)
                  ProfileHighlightsWidget(userId: user.id, isOwnProfile: true),
                  const SizedBox(height: 16),
                  // Tabs: Posts và Tagged
                  _buildProfileTabs(context, theme, user),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Posts sẽ được hiển thị trong tabs - xem _buildProfileTabs
          const SliverToBoxAdapter(child: SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _buildProfileTabs(BuildContext context, ThemeData theme, UserModel user) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(text: 'Bài viết'),
              Tab(text: 'Được gắn thẻ'),
            ],
            labelColor: theme.primaryColor,
            unselectedLabelColor: theme.textTheme.bodySmall?.color,
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: TabBarView(
              children: [
                // Tab 1: User's posts (including tagged posts)
                StreamBuilder<List<PostModel>>(
                  stream: FirestoreService().getAllPostsForUser(user.id, viewerId: user.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Text(
                          AppLocalizations.of(context)?.noPosts ?? 'Chưa có bài viết nào',
                          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                        ),
                      );
                    }

                    final posts = snapshot.data!;
                    return ListView.builder(
                      itemCount: posts.length,
                      itemBuilder: (context, index) {
                        return PostCard(post: posts[index]);
                      },
                    );
                  },
                ),
                // Tab 2: Tagged posts
                TaggedPostsScreen(userId: user.id),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileSettings(BuildContext context, ThemeData theme, UserModel user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _ProfileSettingsSheet(theme: theme, user: user),
    );
  }
}

class _ProfileSettingsSheet extends StatelessWidget {
  final ThemeData theme;
  final UserModel user;

  const _ProfileSettingsSheet({required this.theme, required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(2)),
          ),
          // Edit Profile
          ListTile(
            leading: Icon(Icons.edit, color: theme.primaryColor),
            title: Text(
              AppLocalizations.of(context)?.editProfile ?? 'Chỉnh sửa trang cá nhân',
              style: theme.textTheme.bodyLarge,
            ),
            trailing: Icon(Icons.chevron_right, color: theme.iconTheme.color),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen()));
            },
          ),
          // Activity Log
          ListTile(
            leading: Icon(Icons.history, color: theme.primaryColor),
            title: Text('Nhật ký hoạt động', style: theme.textTheme.bodyLarge),
            trailing: Icon(Icons.chevron_right, color: theme.iconTheme.color),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityLogScreen(userId: user.id)));
            },
          ),
          // Social Links
          ListTile(
            leading: Icon(Icons.link, color: theme.primaryColor),
            title: Text('Liên kết mạng xã hội', style: theme.textTheme.bodyLarge),
            subtitle: _buildSocialLinksPreview(),
            trailing: Icon(Icons.chevron_right, color: theme.iconTheme.color),
            onTap: () {
              Navigator.pop(context);
              _showSocialLinksDialog(context, theme);
            },
          ),
          // Blocked Users
          ListTile(
            leading: Icon(Icons.block, color: theme.primaryColor),
            title: Text('Người dùng bị chặn', style: theme.textTheme.bodyLarge),
            trailing: Icon(Icons.chevron_right, color: theme.iconTheme.color),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlockedUsersScreen()));
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildSocialLinksPreview() {
    final links = <String>[];
    if (user.facebookLink != null && user.facebookLink!.isNotEmpty) {
      links.add('Facebook');
    }
    if (user.instagramLink != null && user.instagramLink!.isNotEmpty) {
      links.add('Instagram');
    }
    if (user.twitterLink != null && user.twitterLink!.isNotEmpty) {
      links.add('Twitter');
    }
    if (user.tiktokLink != null && user.tiktokLink!.isNotEmpty) {
      links.add('TikTok');
    }
    if (user.websiteLink != null && user.websiteLink!.isNotEmpty) {
      links.add('Website');
    }

    if (links.isEmpty) {
      return Text('Chưa có liên kết nào', style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 12));
    }

    return Text(
      links.join(', '),
      style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 12),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _showSocialLinksDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Text('Liên kết mạng xã hội', style: theme.textTheme.titleLarge),
        content: ProfileSocialLinksWidget(user: user),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Đóng', style: TextStyle(color: theme.primaryColor)),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      ],
    );
  }
}

class FriendsPreviewSection extends StatefulWidget {
  final String currentUserId;

  const FriendsPreviewSection({super.key, required this.currentUserId});

  @override
  State<FriendsPreviewSection> createState() => _FriendsPreviewSectionState();
}

class _FriendsPreviewSectionState extends State<FriendsPreviewSection> {
  final FriendService _friendService = FriendService();
  final UserService _userService = UserService();

  bool _loading = true;
  List<UserModel> _friends = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final friendIds = await _friendService.getFriends(widget.currentUserId);
      final users = await _userService.getUsersByIds(friendIds);
      if (!mounted) return;
      setState(() {
        _friends = users;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: theme.primaryColor)),
        ),
      );
    }

    if (_friends.isEmpty) {
      return const SizedBox.shrink();
    }

    final previewFriends = _friends.length > 9 ? _friends.sublist(0, 9) : _friends;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(context)?.friends ?? 'Bạn bè',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.textTheme.titleLarge?.color),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsListScreen()));
                },
                child: Text(
                  AppLocalizations.of(context)?.viewAllFriends ?? 'Xem tất cả bạn bè',
                  style: TextStyle(color: theme.primaryColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${_friends.length} người bạn', style: TextStyle(color: theme.textTheme.bodySmall?.color)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: previewFriends.length,
            itemBuilder: (context, index) {
              final friend = previewFriends[index];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => OtherUserProfileScreen(user: friend)));
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: friend.avatarUrl != null
                            ? Image.network(friend.avatarUrl!, fit: BoxFit.cover)
                            : Container(
                                color: theme.dividerColor.withOpacity(0.3),
                                child: Center(
                                  child: Text(
                                    friend.fullName[0].toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: theme.textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      friend.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: theme.textTheme.bodyLarge?.color),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
