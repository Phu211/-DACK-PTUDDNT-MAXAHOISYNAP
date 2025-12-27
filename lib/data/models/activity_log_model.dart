enum ActivityType {
  like,
  comment,
  share,
  follow,
  unfollow,
  postCreated,
  storyCreated,
}

class ActivityLogModel {
  final String id;
  final String userId; // User thực hiện hành động
  final ActivityType type;
  final String? targetUserId; // User bị tác động (nếu có)
  final String? targetPostId; // Post bị tác động (nếu có)
  final String? targetStoryId; // Story bị tác động (nếu có)
  final String? commentId; // Comment ID (nếu type là comment)
  final Map<String, dynamic>? metadata; // Thông tin bổ sung
  final DateTime createdAt;
  final bool isHidden; // User có thể ẩn hoạt động này

  ActivityLogModel({
    required this.id,
    required this.userId,
    required this.type,
    this.targetUserId,
    this.targetPostId,
    this.targetStoryId,
    this.commentId,
    this.metadata,
    required this.createdAt,
    this.isHidden = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type.name,
      'targetUserId': targetUserId,
      'targetPostId': targetPostId,
      'targetStoryId': targetStoryId,
      'commentId': commentId,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
      'isHidden': isHidden,
    };
  }

  factory ActivityLogModel.fromMap(String id, Map<String, dynamic> map) {
    return ActivityLogModel(
      id: id,
      userId: map['userId'] ?? '',
      type: ActivityType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => ActivityType.like,
      ),
      targetUserId: map['targetUserId'],
      targetPostId: map['targetPostId'],
      targetStoryId: map['targetStoryId'],
      commentId: map['commentId'],
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(map['metadata'])
          : null,
      createdAt: DateTime.parse(map['createdAt']),
      isHidden: map['isHidden'] ?? false,
    );
  }
}
