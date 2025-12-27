import 'package:flutter/material.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/profile_view_service.dart';
import '../../../data/services/user_service.dart';
import 'other_user_profile_screen.dart';
import 'package:timeago/timeago.dart' as timeago;

class ProfileViewsListScreen extends StatelessWidget {
  final String userId;

  const ProfileViewsListScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileViewService = ProfileViewService();
    final userService = UserService();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        title: Text(
          'Lượt xem profile',
          style: TextStyle(color: theme.textTheme.titleLarge?.color),
        ),
        iconTheme: theme.iconTheme,
      ),
      body: StreamBuilder<List<ProfileViewModel>>(
        stream: profileViewService.getRecentProfileViews(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Có lỗi xảy ra: ${snapshot.error}',
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              ),
            );
          }

          final views = snapshot.data ?? [];

          if (views.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.visibility_off,
                    size: 64,
                    color: theme.iconTheme.color?.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chưa có lượt xem nào',
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Profile của bạn chưa được ai xem trong 7 ngày qua',
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

          // Lấy danh sách unique viewer IDs
          final uniqueViewerIds = views
              .map((v) => v.viewerUserId)
              .toSet()
              .toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: uniqueViewerIds.length,
            itemBuilder: (context, index) {
              final viewerId = uniqueViewerIds[index];
              // Lấy lượt xem gần nhất của viewer này
              final latestView = views
                  .where((v) => v.viewerUserId == viewerId)
                  .reduce((a, b) => a.viewedAt.isAfter(b.viewedAt) ? a : b);

              return FutureBuilder<UserModel?>(
                future: userService.getUserById(viewerId),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const SizedBox.shrink();
                  }

                  final viewer = userSnapshot.data;
                  if (viewer == null) {
                    return const SizedBox.shrink();
                  }

                  return InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OtherUserProfileScreen(user: viewer),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: theme.dividerColor,
                            backgroundImage: viewer.avatarUrl != null
                                ? NetworkImage(viewer.avatarUrl!)
                                : null,
                            child: viewer.avatarUrl == null
                                ? Text(
                                    viewer.fullName[0].toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: theme.textTheme.bodyLarge?.color,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          // User info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  viewer.fullName,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: theme.textTheme.bodySmall?.color,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      timeago.format(latestView.viewedAt),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Arrow icon
                          Icon(
                            Icons.chevron_right,
                            color: theme.iconTheme.color,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
