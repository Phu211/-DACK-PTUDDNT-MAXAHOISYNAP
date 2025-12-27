import 'package:flutter/foundation.dart';
import 'privacy_model.dart';
import 'story_element_model.dart';

class StoryModel {
  final String id;
  final String userId;
  final String? imageUrl;
  final String? videoUrl;
  final String? text;
  final String? musicUrl; // URL của nhạc nền
  final String? musicName; // Tên bài nhạc
  final PrivacyType privacy; // Privacy setting for the story
  final List<String> hiddenUsers; // Danh sách user IDs bị ẩn story (chỉ áp dụng khi privacy = friends)
  final List<String> allowedUsers; // Danh sách user IDs được phép xem (chỉ áp dụng khi privacy = custom/closeFriends)
  final List<StorySticker> stickers; // Stickers/emojis on story
  final List<StoryTextOverlay> textOverlays; // Text overlays
  final List<StoryDrawing> drawings; // Drawings
  final List<StoryMention> mentions; // User mentions
  final StoryLink? link; // Link attached to story
  final String? effect; // Filter/effect name
  final DateTime createdAt;
  final DateTime expiresAt; // 24 hours from creation

  StoryModel({
    required this.id,
    required this.userId,
    this.imageUrl,
    this.videoUrl,
    this.text,
    this.musicUrl,
    this.musicName,
    this.privacy = PrivacyType.public,
    this.hiddenUsers = const [],
    this.allowedUsers = const [],
    this.stickers = const [],
    this.textOverlays = const [],
    this.drawings = const [],
    this.mentions = const [],
    this.link,
    this.effect,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired {
    final now = DateTime.now();
    final isExpired = now.isAfter(expiresAt);
    // Debug log để kiểm tra
    if (kDebugMode && isExpired) {
      debugPrint('Story $id is expired: now=$now, expiresAt=$expiresAt, difference=${now.difference(expiresAt).inHours} hours');
    }
    return isExpired;
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'text': text,
      'musicUrl': musicUrl,
      'musicName': musicName,
      'privacy': privacy.toValue(),
      'hiddenUsers': hiddenUsers,
      'allowedUsers': allowedUsers,
      'stickers': stickers.map((s) => s.toMap()).toList(),
      'textOverlays': textOverlays.map((t) => t.toMap()).toList(),
      'drawings': drawings.map((d) => d.toMap()).toList(),
      'mentions': mentions.map((m) => m.toMap()).toList(),
      'link': link?.toMap(),
      'effect': effect,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  factory StoryModel.fromMap(String id, Map<String, dynamic> map) {
    return StoryModel(
      id: id,
      userId: map['userId'] ?? '',
      imageUrl: map['imageUrl'],
      videoUrl: map['videoUrl'],
      text: map['text'],
      musicUrl: map['musicUrl'],
      musicName: map['musicName'],
      privacy: PrivacyTypeExtension.fromString(map['privacy'] ?? 'public') ?? PrivacyType.public,
      hiddenUsers: (map['hiddenUsers'] as List<dynamic>?)
              ?.map((id) => id.toString())
              .toList() ??
          [],
      allowedUsers: (map['allowedUsers'] as List<dynamic>?)
              ?.map((id) => id.toString())
              .toList() ??
          [],
      stickers: (map['stickers'] as List<dynamic>?)
              ?.map((s) => StorySticker.fromMap(s as Map<String, dynamic>))
              .toList() ??
          [],
      textOverlays: (map['textOverlays'] as List<dynamic>?)
              ?.map((t) => StoryTextOverlay.fromMap(t as Map<String, dynamic>))
              .toList() ??
          [],
      drawings: (map['drawings'] as List<dynamic>?)
              ?.map((d) => StoryDrawing.fromMap(d as Map<String, dynamic>))
              .toList() ??
          [],
      mentions: (map['mentions'] as List<dynamic>?)
              ?.map((m) => StoryMention.fromMap(m as Map<String, dynamic>))
              .toList() ??
          [],
      link: map['link'] != null
          ? StoryLink.fromMap(map['link'] as Map<String, dynamic>)
          : null,
      effect: map['effect'],
      createdAt: DateTime.parse(map['createdAt']),
      expiresAt: DateTime.parse(map['expiresAt']),
    );
  }
}


