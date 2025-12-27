import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../post/post_detail_screen.dart';
import '../profile/other_user_profile_screen.dart';
import '../friends/friend_requests_screen.dart';
import '../../../flutter_gen/gen_l10n/app_localizations.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context);
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final notificationService = NotificationService();
    final userService = UserService();

    if (currentUser == null) {
      return Scaffold(body: Center(child: Text(strings?.loginRequired ?? 'Vui lòng đăng nhập')));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        title: Text(
          strings?.notificationsTitle ?? 'Thông báo',
          style: TextStyle(color: theme.textTheme.titleLarge?.color),
        ),
        actions: [
          // Settings button removed as per user request
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: notificationService.getNotifications(currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: theme.primaryColor));
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    strings?.notificationsLoadError ?? 'Không thể tải thông báo',
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Lỗi: ${snapshot.error}',
                      style: TextStyle(color: theme.textTheme.bodySmall?.color),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text(
                strings?.notificationsEmpty ?? 'Chưa có thông báo nào',
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              ),
            );
          }

          final notifications = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return FutureBuilder<UserModel?>(
                future: userService.getUserById(notification.actorId),
                builder: (context, userSnapshot) {
                  final actor = userSnapshot.data;

                  return _NotificationItem(
                    notification: notification,
                    actor: actor,
                    onTap: () async {
                      // Mark as read
                      await notificationService.markAsRead(notification.id);

                      // Navigate based on type
                      if (!context.mounted) return;

                      if (notification.postId != null) {
                        // Các loại like/comment/share/mention đều gắn với postId
                        final authProvider = context.read<AuthProvider>();
                        final currentUser = authProvider.currentUser;
                        final post = await FirestoreService().getPost(notification.postId!, viewerId: currentUser?.id);
                        if (post != null && context.mounted) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
                        }
                      } else {
                        switch (notification.type) {
                          case NotificationType.follow:
                            if (actor != null) {
                              Navigator.of(
                                context,
                              ).push(MaterialPageRoute(builder: (_) => OtherUserProfileScreen(user: actor)));
                            }
                            break;
                          case NotificationType.friendRequest:
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendRequestsScreen()));
                            break;
                          case NotificationType.like:
                          case NotificationType.comment:
                          case NotificationType.reply:
                          case NotificationType.share:
                          case NotificationType.mention:
                            // Không có postId thì chỉ đánh dấu đã đọc, không điều hướng
                            break;
                        }
                      }
                    },
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

class _NotificationItem extends StatelessWidget {
  final NotificationModel notification;
  final UserModel? actor;
  final VoidCallback onTap;

  const _NotificationItem({required this.notification, required this.actor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = _getNotificationMessage();

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: notification.isRead ? theme.cardColor : theme.cardColor.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: actor?.avatarUrl != null ? NetworkImage(actor!.avatarUrl!) : null,
              child: actor?.avatarUrl == null
                  ? Text(
                      actor?.fullName[0].toUpperCase() ?? '?',
                      style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(notification.createdAt),
                    style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(_getNotificationIcon(), color: theme.iconTheme.color?.withOpacity(0.6), size: 20),
          ],
        ),
      ),
    );
  }

  String _getNotificationMessage() {
    final actorName = actor?.fullName ?? 'Ai đó';

    switch (notification.type) {
      case NotificationType.like:
        return '$actorName đã thích bài viết của bạn';
      case NotificationType.comment:
        return '$actorName đã bình luận bài viết của bạn';
      case NotificationType.reply:
        return '$actorName đã phản hồi bình luận của bạn';
      case NotificationType.follow:
        return '$actorName đã theo dõi bạn';
      case NotificationType.share:
        return '$actorName đã chia sẻ bài viết của bạn';
      case NotificationType.mention:
        return '$actorName đã gắn thẻ bạn trong bài viết';
      case NotificationType.friendRequest:
        return '$actorName đã gửi lời mời kết bạn';
    }
  }

  IconData _getNotificationIcon() {
    switch (notification.type) {
      case NotificationType.like:
        return Icons.favorite;
      case NotificationType.comment:
        return Icons.comment;
      case NotificationType.reply:
        return Icons.reply;
      case NotificationType.follow:
        return Icons.person_add;
      case NotificationType.share:
        return Icons.share;
      case NotificationType.mention:
        return Icons.label;
      case NotificationType.friendRequest:
        return Icons.person_add;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.day}/${date.month}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ngày trước';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} phút trước';
    } else {
      return 'Vừa xong';
    }
  }
}
