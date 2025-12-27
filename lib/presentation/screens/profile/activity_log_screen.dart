import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../data/models/activity_log_model.dart';
import '../../../data/services/activity_log_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/firestore_service.dart';
import '../post/post_detail_screen.dart';
import 'package:timeago/timeago.dart' as timeago;

class ActivityLogScreen extends StatelessWidget {
  final String userId;

  const ActivityLogScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activityLogService = ActivityLogService();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        title: Text(
          'Nhật ký hoạt động',
          style: TextStyle(color: theme.textTheme.titleLarge?.color),
        ),
        iconTheme: theme.iconTheme,
      ),
      body: StreamBuilder<List<ActivityLogModel>>(
        stream: activityLogService.getActivityLogs(userId),
        builder: (context, snapshot) {
          if (kDebugMode) {
            print(
              'ActivityLogScreen: connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}, hasError=${snapshot.hasError}, dataLength=${snapshot.data?.length ?? 0}',
            );
            if (snapshot.hasError) {
              print('ActivityLogScreen: error=${snapshot.error}');
            }
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Có lỗi xảy ra',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: theme.iconTheme.color?.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chưa có hoạt động nào',
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Các hoạt động của bạn sẽ hiển thị ở đây',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final activities = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: activities.length,
            itemBuilder: (context, index) {
              final activity = activities[index];
              // Với follow/unfollow, cần lấy thông tin của người được follow/unfollow
              // Với các activity khác, không cần lấy thông tin user vì đây là hoạt động của chính user
              final needsTargetUser = activity.type == ActivityType.follow ||
                  activity.type == ActivityType.unfollow;
              
              if (needsTargetUser && activity.targetUserId != null) {
                return FutureBuilder<UserModel?>(
                  future: UserService().getUserById(activity.targetUserId!),
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: theme.dividerColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 16,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: theme.dividerColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 12,
                                    width: 100,
                                    decoration: BoxDecoration(
                                      color: theme.dividerColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final targetUser = userSnapshot.data;
                    return _buildActivityItem(context, theme, activity, targetUser);
                  },
                );
              }
              
              return _buildActivityItem(context, theme, activity, null);
            },
          );
        },
      ),
    );
  }

  Widget _buildActivityItem(
    BuildContext context,
    ThemeData theme,
    ActivityLogModel activity,
    UserModel? user,
  ) {
    String title = '';
    IconData icon = Icons.info;
    Color? iconColor = theme.primaryColor;

    switch (activity.type) {
      case ActivityType.like:
        title = 'Bạn đã thích một bài viết';
        icon = Icons.favorite;
        iconColor = Colors.red;
        break;
      case ActivityType.comment:
        title = 'Bạn đã bình luận một bài viết';
        icon = Icons.comment;
        iconColor = Colors.blue;
        break;
      case ActivityType.share:
        title = 'Bạn đã chia sẻ một bài viết';
        icon = Icons.share;
        iconColor = Colors.green;
        break;
      case ActivityType.follow:
        title = user != null
            ? 'Bạn đã theo dõi ${user.fullName}'
            : 'Bạn đã theo dõi một người dùng';
        icon = Icons.person_add;
        iconColor = theme.primaryColor;
        break;
      case ActivityType.unfollow:
        title = user != null
            ? 'Bạn đã bỏ theo dõi ${user.fullName}'
            : 'Bạn đã bỏ theo dõi một người dùng';
        icon = Icons.person_remove;
        iconColor = Colors.grey;
        break;
      case ActivityType.postCreated:
        title = 'Bạn đã đăng bài viết';
        icon = Icons.post_add;
        iconColor = theme.primaryColor;
        break;
      case ActivityType.storyCreated:
        title = 'Bạn đã đăng story';
        icon = Icons.auto_stories;
        iconColor = theme.primaryColor;
        break;
    }

    return InkWell(
      onTap: activity.targetPostId != null
          ? () async {
              final post = await FirestoreService().getPost(
                activity.targetPostId!,
                viewerId: userId,
              );
              if (post != null && context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PostDetailScreen(post: post),
                  ),
                );
              }
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.dividerColor.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(activity.createdAt, locale: 'vi'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
