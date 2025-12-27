enum GroupRole {
  admin,
  moderator,
  member,
}

enum GroupType {
  post, // Nhóm đăng bài (từ Menu)
  chat, // Nhóm nhắn tin (từ Messages)
}

class GroupModel {
  final String id;
  final String name;
  final String? description;
  final String? coverUrl;
  final String creatorId;
  final List<String> memberIds;
  final Map<String, GroupRole> memberRoles; // userId -> role
  final bool isPublic;
  final GroupType type; // Loại nhóm: post hoặc chat
  final DateTime createdAt;
  final DateTime updatedAt;

  GroupModel({
    required this.id,
    required this.name,
    this.description,
    this.coverUrl,
    required this.creatorId,
    this.memberIds = const [],
    this.memberRoles = const {},
    this.isPublic = true,
    this.type = GroupType.post, // Mặc định là nhóm đăng bài
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'coverUrl': coverUrl,
      'creatorId': creatorId,
      'memberIds': memberIds,
      'memberRoles': memberRoles.map((k, v) => MapEntry(k, v.name)),
      'isPublic': isPublic,
      'type': type.name, // 'post' hoặc 'chat'
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory GroupModel.fromMap(String id, Map<String, dynamic> map) {
    final roles = <String, GroupRole>{};
    if (map['memberRoles'] != null) {
      (map['memberRoles'] as Map).forEach((k, v) {
        roles[k] = GroupRole.values.firstWhere(
          (e) => e.name == v,
          orElse: () => GroupRole.member,
        );
      });
    }

    // Parse type, mặc định là 'post' nếu không có hoặc không hợp lệ
    GroupType groupType = GroupType.post;
    if (map['type'] != null) {
      try {
        groupType = GroupType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => GroupType.post,
        );
      } catch (e) {
        groupType = GroupType.post;
      }
    }

    return GroupModel(
      id: id,
      name: map['name'] ?? '',
      description: map['description'],
      coverUrl: map['coverUrl'],
      creatorId: map['creatorId'] ?? '',
      memberIds: List<String>.from(map['memberIds'] ?? []),
      memberRoles: roles,
      isPublic: map['isPublic'] ?? true,
      type: groupType,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }
}


