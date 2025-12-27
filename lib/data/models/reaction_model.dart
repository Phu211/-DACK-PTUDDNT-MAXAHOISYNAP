enum ReactionType {
  like,
  love,
  care,
  haha,
  wow,
  sad,
  angry,
}

extension ReactionTypeExtension on ReactionType {
  String get emoji {
    switch (this) {
      case ReactionType.like:
        return '👍';
      case ReactionType.love:
        return '❤️';
      case ReactionType.care:
        return '🤗';
      case ReactionType.haha:
        return '😂';
      case ReactionType.wow:
        return '😮';
      case ReactionType.sad:
        return '😢';
      case ReactionType.angry:
        return '😠';
    }
  }

  String get name {
    switch (this) {
      case ReactionType.like:
        return 'Thích';
      case ReactionType.love:
        return 'Yêu thích';
      case ReactionType.care:
        return 'Quan tâm';
      case ReactionType.haha:
        return 'Haha';
      case ReactionType.wow:
        return 'Wow';
      case ReactionType.sad:
        return 'Buồn';
      case ReactionType.angry:
        return 'Phẫn nộ';
    }
  }

  static ReactionType? fromString(String value) {
    switch (value) {
      case 'like':
        return ReactionType.like;
      case 'love':
        return ReactionType.love;
      case 'care':
        return ReactionType.care;
      case 'haha':
        return ReactionType.haha;
      case 'wow':
        return ReactionType.wow;
      case 'sad':
        return ReactionType.sad;
      case 'angry':
        return ReactionType.angry;
      default:
        return null;
    }
  }

  String toValue() {
    switch (this) {
      case ReactionType.like:
        return 'like';
      case ReactionType.love:
        return 'love';
      case ReactionType.care:
        return 'care';
      case ReactionType.haha:
        return 'haha';
      case ReactionType.wow:
        return 'wow';
      case ReactionType.sad:
        return 'sad';
      case ReactionType.angry:
        return 'angry';
    }
  }
}

class ReactionModel {
  final String id;
  final String postId;
  final String userId;
  final ReactionType type;
  final DateTime createdAt;

  ReactionModel({
    required this.id,
    required this.postId,
    required this.userId,
    required this.type,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'postId': postId,
      'userId': userId,
      'type': type.toValue(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ReactionModel.fromMap(String id, Map<String, dynamic> map) {
    return ReactionModel(
      id: id,
      postId: map['postId'] ?? '',
      userId: map['userId'] ?? '',
      type: ReactionTypeExtension.fromString(map['type'] ?? 'like') ?? ReactionType.like,
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}


