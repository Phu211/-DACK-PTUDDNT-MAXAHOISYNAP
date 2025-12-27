import 'privacy_model.dart';

class StoryPrivacySettings {
  final PrivacyType privacy;
  final List<String> hiddenUsers; // Danh sách user IDs bị ẩn story
  final List<String> allowedUsers; // Danh sách user IDs được phép xem (Close Friends)

  StoryPrivacySettings({
    required this.privacy,
    this.hiddenUsers = const [],
    this.allowedUsers = const [],
  });

  StoryPrivacySettings copyWith({
    PrivacyType? privacy,
    List<String>? hiddenUsers,
    List<String>? allowedUsers,
  }) {
    return StoryPrivacySettings(
      privacy: privacy ?? this.privacy,
      hiddenUsers: hiddenUsers ?? this.hiddenUsers,
      allowedUsers: allowedUsers ?? this.allowedUsers,
    );
  }
}


