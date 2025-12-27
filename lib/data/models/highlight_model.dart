class HighlightModel {
  final String id;
  final String userId;
  final String title;
  final String? iconName; // Tên icon (emoji hoặc icon name)
  final String? coverImageUrl; // Ảnh cover cho highlight
  final List<String> storyIds; // Danh sách story IDs trong highlight
  final DateTime createdAt;
  final DateTime updatedAt;

  HighlightModel({
    required this.id,
    required this.userId,
    required this.title,
    this.iconName,
    this.coverImageUrl,
    this.storyIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'iconName': iconName,
      'coverImageUrl': coverImageUrl,
      'storyIds': storyIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory HighlightModel.fromMap(String id, Map<String, dynamic> map) {
    return HighlightModel(
      id: id,
      userId: map['userId'] ?? '',
      title: map['title'] ?? '',
      iconName: map['iconName'],
      coverImageUrl: map['coverImageUrl'],
      storyIds: List<String>.from(map['storyIds'] ?? []),
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  HighlightModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? iconName,
    String? coverImageUrl,
    List<String>? storyIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HighlightModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      iconName: iconName ?? this.iconName,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      storyIds: storyIds ?? this.storyIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
