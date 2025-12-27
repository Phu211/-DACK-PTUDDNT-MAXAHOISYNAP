/// Model để lưu các tương tác của user để tính toán recommendations
class UserInteractionModel {
  final String userId;
  final String targetId; // ID của post/user/group/etc
  final String targetType; // 'post', 'user', 'group', 'video', 'page', 'product'
  final InteractionType type;
  final double weight; // Trọng số của tương tác (1.0 = like, 2.0 = comment, 0.5 = view)
  final int duration; // Thời gian xem (seconds) cho video
  final DateTime timestamp;

  UserInteractionModel({
    required this.userId,
    required this.targetId,
    required this.targetType,
    required this.type,
    this.weight = 1.0,
    this.duration = 0,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'targetId': targetId,
      'targetType': targetType,
      'type': type.name,
      'weight': weight,
      'duration': duration,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory UserInteractionModel.fromMap(Map<String, dynamic> map) {
    return UserInteractionModel(
      userId: map['userId'] ?? '',
      targetId: map['targetId'] ?? '',
      targetType: map['targetType'] ?? '',
      type: InteractionType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => InteractionType.view,
      ),
      weight: (map['weight'] ?? 1.0).toDouble(),
      duration: map['duration'] ?? 0,
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}

enum InteractionType {
  view,      // Xem (weight: 0.5)
  like,      // Thích (weight: 1.0)
  comment,   // Bình luận (weight: 2.0)
  share,     // Chia sẻ (weight: 3.0)
  watch,     // Xem video (weight: 1.0 + duration bonus)
  follow,    // Theo dõi (weight: 5.0)
  purchase,  // Mua hàng (weight: 10.0)
}

extension InteractionTypeExtension on InteractionType {
  double get defaultWeight {
    switch (this) {
      case InteractionType.view:
        return 0.5;
      case InteractionType.like:
        return 1.0;
      case InteractionType.comment:
        return 2.0;
      case InteractionType.share:
        return 3.0;
      case InteractionType.watch:
        return 1.0;
      case InteractionType.follow:
        return 5.0;
      case InteractionType.purchase:
        return 10.0;
    }
  }
}


