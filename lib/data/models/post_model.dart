import 'privacy_model.dart';

class PostModel {
  final String id;
  final String userId;
  final String content;
  // Trường phục vụ search nội dung
  String get searchContent => _normalize(content);
  final List<String> mediaUrls;
  final String? videoUrl; // Video URL for posts
  final String? gifUrl; // GIF URL from GIPHY
  final String? location;
  final List<String> hashtags;
  final List<String> taggedUserIds; // List of user IDs who are tagged in this post
  final String? feeling; // User's feeling/emotion (e.g., "😊 Vui vẻ", "😍 Yêu thích")
  final String? milestoneCategory; // Life event category (e.g., "Công việc", "Học vấn")
  final String? milestoneEvent; // Life event type (e.g., "Công việc mới", "Thăng chức")
  final List<String> removedTaggedUserIds; // List of user IDs who removed themselves from the tag
  final String? musicTrackId; // Spotify track ID
  final String? musicName; // Track name
  final String? musicArtist; // Artist name
  final String? musicPreviewUrl; // Preview URL
  final String? musicImageUrl; // Album cover image
  final String? musicExternalUrl; // Spotify external URL
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final String? sharedPostId; // ID of the original post if this is a shared post
  final String? groupId; // ID of the group if this post belongs to a group
  final PrivacyType privacy; // Privacy setting for the post
  final DateTime createdAt;
  final DateTime updatedAt;

  PostModel({
    required this.id,
    required this.userId,
    required this.content,
    this.mediaUrls = const [],
    this.videoUrl,
    this.gifUrl,
    this.location,
    this.hashtags = const [],
    this.taggedUserIds = const [],
    this.removedTaggedUserIds = const [],
    this.feeling,
    this.milestoneCategory,
    this.milestoneEvent,
    this.musicTrackId,
    this.musicName,
    this.musicArtist,
    this.musicPreviewUrl,
    this.musicImageUrl,
    this.musicExternalUrl,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    this.sharedPostId,
    this.groupId,
    this.privacy = PrivacyType.public,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'content': content,
      'searchContent': searchContent,
      'mediaUrls': mediaUrls,
      'videoUrl': videoUrl,
      'gifUrl': gifUrl,
      'location': location,
      'hashtags': hashtags,
      'taggedUserIds': taggedUserIds,
      'removedTaggedUserIds': removedTaggedUserIds,
      'feeling': feeling,
      'milestoneCategory': milestoneCategory,
      'milestoneEvent': milestoneEvent,
      'musicTrackId': musicTrackId,
      'musicName': musicName,
      'musicArtist': musicArtist,
      'musicPreviewUrl': musicPreviewUrl,
      'musicImageUrl': musicImageUrl,
      'musicExternalUrl': musicExternalUrl,
      'likesCount': likesCount,
      'commentsCount': commentsCount,
      'sharesCount': sharesCount,
      'sharedPostId': sharedPostId,
      'groupId': groupId,
      'privacy': privacy.toValue(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Create from Firestore document
  factory PostModel.fromMap(String id, Map<String, dynamic> map) {
    return PostModel(
      id: id,
      userId: map['userId'] ?? '',
      content: map['content'] ?? '',
      mediaUrls: List<String>.from(map['mediaUrls'] ?? []),
      videoUrl: map['videoUrl'],
      gifUrl: map['gifUrl'],
      location: map['location'],
      hashtags: List<String>.from(map['hashtags'] ?? []),
      taggedUserIds: List<String>.from(map['taggedUserIds'] ?? []),
      removedTaggedUserIds: List<String>.from(map['removedTaggedUserIds'] ?? []),
      feeling: map['feeling'],
      milestoneCategory: map['milestoneCategory'],
      milestoneEvent: map['milestoneEvent'],
      musicTrackId: map['musicTrackId'],
      musicName: map['musicName'],
      musicArtist: map['musicArtist'],
      musicPreviewUrl: map['musicPreviewUrl'],
      musicImageUrl: map['musicImageUrl'],
      musicExternalUrl: map['musicExternalUrl'],
      likesCount: map['likesCount'] ?? 0,
      commentsCount: map['commentsCount'] ?? 0,
      sharesCount: map['sharesCount'] ?? 0,
      sharedPostId: map['sharedPostId'],
      groupId: map['groupId'],
      privacy: PrivacyTypeExtension.fromString(map['privacy'] ?? 'public') ?? PrivacyType.public,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  // Copy with method
  PostModel copyWith({
    String? id,
    String? userId,
    String? content,
    List<String>? mediaUrls,
    String? videoUrl,
    String? gifUrl,
    String? location,
    List<String>? hashtags,
    List<String>? taggedUserIds,
    List<String>? removedTaggedUserIds,
    String? feeling,
    String? milestoneCategory,
    String? milestoneEvent,
    String? musicTrackId,
    String? musicName,
    String? musicArtist,
    String? musicPreviewUrl,
    String? musicImageUrl,
    String? musicExternalUrl,
    int? likesCount,
    int? commentsCount,
    int? sharesCount,
    String? sharedPostId,
    String? groupId,
    PrivacyType? privacy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PostModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      videoUrl: videoUrl ?? this.videoUrl,
      gifUrl: gifUrl ?? this.gifUrl,
      location: location ?? this.location,
      hashtags: hashtags ?? this.hashtags,
      taggedUserIds: taggedUserIds ?? this.taggedUserIds,
      removedTaggedUserIds: removedTaggedUserIds ?? this.removedTaggedUserIds,
      feeling: feeling ?? this.feeling,
      milestoneCategory: milestoneCategory ?? this.milestoneCategory,
      milestoneEvent: milestoneEvent ?? this.milestoneEvent,
      musicTrackId: musicTrackId ?? this.musicTrackId,
      musicName: musicName ?? this.musicName,
      musicArtist: musicArtist ?? this.musicArtist,
      musicPreviewUrl: musicPreviewUrl ?? this.musicPreviewUrl,
      musicImageUrl: musicImageUrl ?? this.musicImageUrl,
      musicExternalUrl: musicExternalUrl ?? this.musicExternalUrl,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount ?? this.sharesCount,
      sharedPostId: sharedPostId ?? this.sharedPostId,
      groupId: groupId ?? this.groupId,
      privacy: privacy ?? this.privacy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _normalize(String input) {
    final lower = input.toLowerCase();
    const withDiacritics = 'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
    const withoutDiacritics = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuu-yyyyyd';
    var result = '';
    for (var i = 0; i < lower.length; i++) {
      final char = lower[i];
      final index = withDiacritics.indexOf(char);
      result += index >= 0 ? withoutDiacritics[index] : char;
    }
    return result;
  }
}


