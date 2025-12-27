class CommentModel {
  final String id;
  final String postId;
  final String userId;
  final String content;
  final String? gifUrl;
  final String? imageUrl; // URL của ảnh trong bình luận
  final String? emoji; // Emoji icon trong bình luận
  final String? parentId; // For nested comments
  final int likesCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  CommentModel({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    this.gifUrl,
    this.imageUrl,
    this.emoji,
    this.parentId,
    this.likesCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'postId': postId,
      'userId': userId,
      'content': content,
      'gifUrl': gifUrl,
      'imageUrl': imageUrl,
      'emoji': emoji,
      'parentId': parentId,
      'likesCount': likesCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory CommentModel.fromMap(String id, Map<String, dynamic> map) {
    return CommentModel(
      id: id,
      postId: map['postId'] ?? '',
      userId: map['userId'] ?? '',
      content: map['content'] ?? '',
      gifUrl: map['gifUrl'],
      imageUrl: map['imageUrl'],
      emoji: map['emoji'],
      parentId: map['parentId'],
      likesCount: map['likesCount'] ?? 0,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  CommentModel copyWith({
    String? id,
    String? postId,
    String? userId,
    String? content,
    String? gifUrl,
    String? imageUrl,
    String? emoji,
    String? parentId,
    int? likesCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CommentModel(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      gifUrl: gifUrl ?? this.gifUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      emoji: emoji ?? this.emoji,
      parentId: parentId ?? this.parentId,
      likesCount: likesCount ?? this.likesCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}


