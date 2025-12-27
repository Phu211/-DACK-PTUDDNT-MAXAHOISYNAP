class PageModel {
  final String id;
  final String name;
  final String? description;
  final String? coverUrl;
  final String? profileUrl;
  final String creatorId;
  final int followersCount;
  final int likesCount;
  final String? category;
  final String? website;
  final String? location;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime updatedAt;

  PageModel({
    required this.id,
    required this.name,
    this.description,
    this.coverUrl,
    this.profileUrl,
    required this.creatorId,
    this.followersCount = 0,
    this.likesCount = 0,
    this.category,
    this.website,
    this.location,
    this.isVerified = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'coverUrl': coverUrl,
      'profileUrl': profileUrl,
      'creatorId': creatorId,
      'followersCount': followersCount,
      'likesCount': likesCount,
      'category': category,
      'website': website,
      'location': location,
      'isVerified': isVerified,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PageModel.fromMap(String id, Map<String, dynamic> map) {
    return PageModel(
      id: id,
      name: map['name'] ?? '',
      description: map['description'],
      coverUrl: map['coverUrl'],
      profileUrl: map['profileUrl'],
      creatorId: map['creatorId'] ?? '',
      followersCount: map['followersCount'] ?? 0,
      likesCount: map['likesCount'] ?? 0,
      category: map['category'],
      website: map['website'],
      location: map['location'],
      isVerified: map['isVerified'] ?? false,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }
}


