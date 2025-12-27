class UserModel {
  final String id;
  final String email;
  final String username;
  final String fullName;
  // Fields phục vụ search
  String get searchName => _normalize(fullName);
  String get searchUsername => username.toLowerCase();
  final String? bio;
  final String? avatarUrl;
  final String? coverUrl;
  final bool isPrivate;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  // Info Cards
  final String? workplace; // Nơi làm việc
  final String? education; // Học vấn
  final String? location; // Nơi sống
  final String? hometown; // Quê quán
  final DateTime? birthday; // Ngày sinh
  final String? relationshipStatus; // Mối quan hệ
  // Social Links
  final String? facebookLink;
  final String? instagramLink;
  final String? twitterLink;
  final String? tiktokLink;
  final String? websiteLink;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    this.bio,
    this.avatarUrl,
    this.coverUrl,
    this.isPrivate = false,
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.workplace,
    this.education,
    this.location,
    this.hometown,
    this.birthday,
    this.relationshipStatus,
    this.facebookLink,
    this.instagramLink,
    this.twitterLink,
    this.tiktokLink,
    this.websiteLink,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'username': username,
      'fullName': fullName,
      'searchName': searchName,
      'searchUsername': searchUsername,
      'bio': bio,
      'avatarUrl': avatarUrl,
      'coverUrl': coverUrl,
      'isPrivate': isPrivate,
      'followersCount': followersCount,
      'followingCount': followingCount,
      'postsCount': postsCount,
      'workplace': workplace,
      'education': education,
      'location': location,
      'hometown': hometown,
      'birthday': birthday?.toIso8601String(),
      'relationshipStatus': relationshipStatus,
      'facebookLink': facebookLink,
      'instagramLink': instagramLink,
      'twitterLink': twitterLink,
      'tiktokLink': tiktokLink,
      'websiteLink': websiteLink,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Create from Firestore document
  factory UserModel.fromMap(String id, Map<String, dynamic> map) {
    return UserModel(
      id: id,
      email: map['email'] ?? '',
      username: map['username'] ?? '',
      fullName: map['fullName'] ?? '',
      bio: map['bio'],
      avatarUrl: map['avatarUrl'],
      coverUrl: map['coverUrl'],
      isPrivate: map['isPrivate'] ?? false,
      followersCount: map['followersCount'] ?? 0,
      followingCount: map['followingCount'] ?? 0,
      postsCount: map['postsCount'] ?? 0,
      workplace: map['workplace'],
      education: map['education'],
      location: map['location'],
      hometown: map['hometown'],
      birthday: map['birthday'] != null
          ? DateTime.parse(map['birthday'])
          : null,
      relationshipStatus: map['relationshipStatus'],
      facebookLink: map['facebookLink'],
      instagramLink: map['instagramLink'],
      twitterLink: map['twitterLink'],
      tiktokLink: map['tiktokLink'],
      websiteLink: map['websiteLink'],
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  // Copy with method
  UserModel copyWith({
    String? id,
    String? email,
    String? username,
    String? fullName,
    String? bio,
    String? avatarUrl,
    String? coverUrl,
    bool? isPrivate,
    int? followersCount,
    int? followingCount,
    int? postsCount,
    String? workplace,
    String? education,
    String? location,
    String? hometown,
    DateTime? birthday,
    String? relationshipStatus,
    String? facebookLink,
    String? instagramLink,
    String? twitterLink,
    String? tiktokLink,
    String? websiteLink,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      isPrivate: isPrivate ?? this.isPrivate,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      postsCount: postsCount ?? this.postsCount,
      workplace: workplace ?? this.workplace,
      education: education ?? this.education,
      location: location ?? this.location,
      hometown: hometown ?? this.hometown,
      birthday: birthday ?? this.birthday,
      relationshipStatus: relationshipStatus ?? this.relationshipStatus,
      facebookLink: facebookLink ?? this.facebookLink,
      instagramLink: instagramLink ?? this.instagramLink,
      twitterLink: twitterLink ?? this.twitterLink,
      tiktokLink: tiktokLink ?? this.tiktokLink,
      websiteLink: websiteLink ?? this.websiteLink,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Chuẩn hóa chuỗi để search (lowercase + bỏ dấu cơ bản)
  static String _normalize(String input) {
    final lower = input.toLowerCase();
    // Bỏ dấu tiếng Việt đơn giản
    const withDiacritics =
        'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
    const withoutDiacritics =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuu-yyyyyd';
    var result = '';
    for (var i = 0; i < lower.length; i++) {
      final char = lower[i];
      final index = withDiacritics.indexOf(char);
      result += index >= 0 ? withoutDiacritics[index] : char;
    }
    return result;
  }
}
