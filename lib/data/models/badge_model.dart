enum BadgeType {
  newUser, // Người mới
  activeUser, // Người tích cực
  topCreator, // Top creator
  popular, // Nổi tiếng (nhiều followers)
  verified, // Đã xác minh
  earlyAdopter, // Người dùng sớm
}

class BadgeModel {
  final BadgeType type;
  final String name;
  final String description;
  final String icon; // Emoji hoặc icon name
  final DateTime? earnedAt; // Thời gian đạt được

  BadgeModel({
    required this.type,
    required this.name,
    required this.description,
    required this.icon,
    this.earnedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'name': name,
      'description': description,
      'icon': icon,
      'earnedAt': earnedAt?.toIso8601String(),
    };
  }

  factory BadgeModel.fromMap(Map<String, dynamic> map) {
    return BadgeModel(
      type: BadgeType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => BadgeType.newUser,
      ),
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      icon: map['icon'] ?? '🏆',
      earnedAt: map['earnedAt'] != null
          ? DateTime.parse(map['earnedAt'])
          : null,
    );
  }
}
