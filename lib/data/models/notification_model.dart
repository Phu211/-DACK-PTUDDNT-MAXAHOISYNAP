enum NotificationType {
  like,
  comment,
  reply,
  follow,
  share,
  mention,
  friendRequest,
}

class NotificationModel {
  final String id;
  final String userId; // User who receives the notification
  final String actorId; // User who performed the action
  final NotificationType type;
  final String? postId;
  final String? commentId;
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.actorId,
    required this.type,
    this.postId,
    this.commentId,
    this.isRead = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'actorId': actorId,
      'type': type.toString().split('.').last,
      'postId': postId,
      'commentId': commentId,
      'isRead': isRead,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory NotificationModel.fromMap(String id, Map<String, dynamic> map) {
    NotificationType type;
    switch (map['type']) {
      case 'like':
        type = NotificationType.like;
        break;
      case 'comment':
        type = NotificationType.comment;
        break;
      case 'reply':
        type = NotificationType.reply;
        break;
      case 'follow':
        type = NotificationType.follow;
        break;
      case 'share':
        type = NotificationType.share;
        break;
      case 'mention':
        type = NotificationType.mention;
        break;
      case 'friendRequest':
        type = NotificationType.friendRequest;
        break;
      default:
        type = NotificationType.like;
    }

    return NotificationModel(
      id: id,
      userId: map['userId'] ?? '',
      actorId: map['actorId'] ?? '',
      type: type,
      postId: map['postId'],
      commentId: map['commentId'],
      isRead: map['isRead'] ?? false,
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}


