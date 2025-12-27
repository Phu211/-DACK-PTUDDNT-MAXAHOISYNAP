import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../../data/models/story_model.dart';
import '../../data/models/user_model.dart';
import '../../data/services/story_service.dart';
import '../../data/services/friend_service.dart';
import '../../data/services/user_service.dart';
import '../screens/stories/create_story_screen.dart';
import '../screens/stories/story_viewer_screen.dart';

class StoriesSection extends StatelessWidget {
  const StoriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final storyService = StoryService();
    final friendService = FriendService();

    if (currentUser == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return SizedBox(
      height: 140, // constrain height so horizontal ListView has bounds
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 0),
        margin: const EdgeInsets.only(bottom: 0),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(
            bottom: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: FutureBuilder<List<String>>(
          future: friendService.getFriends(currentUser.id),
          builder: (context, friendsSnapshot) {
            final friendIds = [
              ...?friendsSnapshot.data,
              currentUser.id,
            ]; // Include current user's stories

            return StreamBuilder<List<StoryModel>>(
              stream: storyService.getActiveStories(
                friendIds,
                currentUserId: currentUser.id,
              ),
              builder: (context, storiesSnapshot) {
                final stories = storiesSnapshot.data ?? [];

                // Group stories by user
                final storiesByUser = <String, List<StoryModel>>{};
                for (final story in stories) {
                  storiesByUser.putIfAbsent(story.userId, () => []).add(story);
                }

                // Sắp xếp stories của mỗi user theo thời gian (mới nhất trước)
                for (final entry in storiesByUser.entries) {
                  entry.value.sort(
                    (a, b) => b.createdAt.compareTo(a.createdAt),
                  );
                }

                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Create story
                    _StoryItem(
                      isCreateStory: true,
                      userName: currentUser.fullName,
                      userAvatarUrl: currentUser.avatarUrl,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CreateStoryScreen(),
                          ),
                        );
                      },
                    ),
                    // Other stories - Load users first to avoid nested FutureBuilder
                    ...storiesByUser.entries.map((entry) {
                      // Lấy story mới nhất (đã sắp xếp) để hiển thị preview
                      final latestStory = entry.value.first;
                      final storyCount = entry.value.length;
                      final userId =
                          entry.key; // Store userId to ensure consistency

                      return _StoryItem(
                        key: ValueKey(
                          'story_$userId',
                        ), // Unique key for each story item
                        isCreateStory: false,
                        userName: null, // Will be loaded separately
                        storyImageUrl: latestStory.imageUrl,
                        videoUrl: latestStory.videoUrl,
                        avatarUrl: null, // Will be loaded separately
                        userId: userId, // Pass userId to load user data
                        storyCount: storyCount > 1
                            ? storyCount
                            : null, // Hiển thị số lượng nếu > 1
                        onTap: () async {
                          // Load danh sách users có stories
                          final friendIds = [
                            ...?friendsSnapshot.data,
                            currentUser.id,
                          ];
                          final allStories = await storyService
                              .getActiveStories(
                                friendIds,
                                currentUserId: currentUser.id,
                              )
                              .first;

                          // Group stories by user và lấy danh sách userIds
                          final storiesByUserForNav =
                              <String, List<StoryModel>>{};
                          for (final story in allStories) {
                            storiesByUserForNav
                                .putIfAbsent(story.userId, () => [])
                                .add(story);
                          }
                          final usersWithStories = storiesByUserForNav.keys
                              .toList();
                          final currentUserIndex = usersWithStories.indexOf(
                            userId,
                          );

                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StoryViewerScreen(
                                userId: userId,
                                usersWithStories: usersWithStories,
                                initialUserIndex: currentUserIndex >= 0
                                    ? currentUserIndex
                                    : 0,
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _StoryItem extends StatefulWidget {
  final bool isCreateStory;
  final String? userName;
  final String? userAvatarUrl;
  final String? storyImageUrl;
  final String? videoUrl;
  final String? avatarUrl;
  final String? userId;
  final int? storyCount; // Số lượng stories (hiển thị nếu > 1)
  final VoidCallback onTap;

  const _StoryItem({
    super.key,
    required this.isCreateStory,
    this.userName,
    this.userAvatarUrl,
    this.storyImageUrl,
    this.videoUrl,
    this.avatarUrl,
    this.userId,
    this.storyCount,
    required this.onTap,
  });

  @override
  State<_StoryItem> createState() => _StoryItemState();
}

class _StoryItemState extends State<_StoryItem> {
  UserModel? _user;
  bool _isLoadingUser = false;

  @override
  void initState() {
    super.initState();
    if (widget.userId != null && !widget.isCreateStory) {
      _loadUser();
    }
  }

  @override
  void didUpdateWidget(_StoryItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload user if userId changed
    if (widget.userId != null &&
        widget.userId != oldWidget.userId &&
        !widget.isCreateStory &&
        !_isLoadingUser) {
      _user = null; // Clear old user data
      _loadUser();
    }
  }

  Future<void> _loadUser() async {
    if (widget.userId == null || _isLoadingUser) return;

    setState(() {
      _isLoadingUser = true;
    });

    try {
      final userService = UserService();
      final currentUserId = widget.userId; // Store current userId
      final user = await userService.getUserById(currentUserId!);
      if (mounted && widget.userId == currentUserId) {
        // Double check userId hasn't changed
        setState(() {
          _user = user;
          _isLoadingUser = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingUser = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userName = widget.userName ?? _user?.fullName;
    final avatarUrl = widget.avatarUrl ?? _user?.avatarUrl;
    // Dùng avatar làm nền nếu story là video nhưng không có imageUrl
    final coverImageUrl =
        widget.storyImageUrl ?? (widget.videoUrl != null ? avatarUrl : null);
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 68,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(color: Colors.transparent),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Story circle with plus icon
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: widget.isCreateStory
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.dividerColor,
                            width: 1,
                          ),
                        )
                      : BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFFF59E0B), // amber-500
                              const Color(0xFFEC4899), // pink-500
                              const Color(0xFF8B5CF6), // purple-500
                            ],
                          ),
                        ),
                  padding: widget.isCreateStory
                      ? const EdgeInsets.all(1)
                      : const EdgeInsets.all(2),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: widget.isCreateStory
                          ? null
                          : Border.all(
                              color: theme.scaffoldBackgroundColor,
                              width: 2,
                            ),
                    ),
                    child: ClipOval(
                      child: widget.isCreateStory
                          ? (widget.userAvatarUrl != null
                                ? Image.network(
                                    widget.userAvatarUrl!,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: theme.cardColor,
                                        child: Icon(Icons.person,
                                            color: theme.iconTheme.color),
                                      );
                                    },
                                  )
                                : Container(
                                    color: theme.cardColor,
                                    child: Icon(Icons.person,
                                        color: theme.iconTheme.color),
                                  ))
                          : (coverImageUrl != null
                                ? Image.network(
                                    coverImageUrl,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: theme.cardColor,
                                        child: Icon(Icons.person,
                                            color: theme.iconTheme.color),
                                      );
                                    },
                                  )
                                : Container(
                                    color: theme.cardColor,
                                    child: Icon(Icons.person,
                                        color: theme.iconTheme.color),
                                  )),
                    ),
                  ),
                ),
                // Plus icon for create story
                if (widget.isCreateStory)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                // Story count badge (nếu có nhiều stories)
                if (!widget.isCreateStory && widget.storyCount != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.storyCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // User name with background for better contrast
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor.withOpacity(0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.isCreateStory
                    ? AppLocalizations.of(context)?.storiesYourStory ?? 'Tin của bạn'
                    : (userName ?? ''),
                style: TextStyle(
                  color: widget.isCreateStory
                      ? theme.textTheme.bodySmall?.color ?? Colors.black87
                      : theme.textTheme.bodyLarge?.color ?? Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      color: Colors.white.withOpacity(0.8),
                      blurRadius: 2,
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
