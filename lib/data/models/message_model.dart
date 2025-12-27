import 'package:flutter/foundation.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final String? imageUrl;
  final String? videoUrl;
  final String? audioUrl;
  final int? audioDuration; // Duration in seconds for voice messages
  final String? gifUrl; // GIF URL from GIPHY
  final bool isRead;
  final String? conversationId;
  final DateTime createdAt;
  final bool isRecalled;
  final DateTime? recalledAt;
  final bool isPinned;
  final DateTime? pinnedAt;
  final Map<String, List<String>> reactions; // emoji -> userIds
  final String status; // sent | delivered | read
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final String? replyToMessageId;
  final String? replyToContent;
  final String? replyToSenderId;
  final String? replyToType; // text|image|video|audio|location
  final String? groupId; // ID của nhóm nếu là tin nhắn nhóm
  // Location sharing fields
  final double? latitude;
  final double? longitude;
  final String? locationAddress; // Human-readable address
  final bool? isLiveLocation; // true if real-time tracking
  final DateTime?
  locationExpiresAt; // null = permanent, otherwise expires at this time
  final List<String>
  deletedBy; // List of user IDs who have deleted this message

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.imageUrl,
    this.videoUrl,
    this.isRead = false,
    this.audioUrl,
    this.audioDuration,
    this.gifUrl,
    this.conversationId,
    required this.createdAt,
    this.isRecalled = false,
    this.recalledAt,
    this.isPinned = false,
    this.pinnedAt,
    this.reactions = const {},
    this.status = 'sent',
    this.deliveredAt,
    this.readAt,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToSenderId,
    this.replyToType,
    this.groupId,
    this.latitude,
    this.longitude,
    this.locationAddress,
    this.isLiveLocation,
    this.locationExpiresAt,
    this.deletedBy = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'audioUrl': audioUrl,
      'audioDuration': audioDuration,
      'gifUrl': gifUrl,
      'isRead': isRead,
      'conversationId': conversationId,
      'createdAt': createdAt.toIso8601String(),
      'isRecalled': isRecalled,
      'recalledAt': recalledAt?.toIso8601String(),
      'isPinned': isPinned,
      'pinnedAt': pinnedAt?.toIso8601String(),
      'reactions': reactions.map((k, v) => MapEntry(k, v)),
      'status': status,
      'deliveredAt': deliveredAt?.toIso8601String(),
      'readAt': readAt?.toIso8601String(),
      'replyToMessageId': replyToMessageId,
      'replyToContent': replyToContent,
      'replyToSenderId': replyToSenderId,
      'replyToType': replyToType,
      'groupId': groupId,
      'latitude': latitude,
      'longitude': longitude,
      'locationAddress': locationAddress,
      'isLiveLocation': isLiveLocation,
      'locationExpiresAt': locationExpiresAt?.toIso8601String(),
      'deletedBy': deletedBy,
    };
  }

  factory MessageModel.fromMap(String id, Map<String, dynamic> map) {
    // Helper function để parse DateTime an toàn
    DateTime? safeParseDateTime(dynamic value) {
      if (value == null) return null;
      try {
        if (value is DateTime) return value;
        if (value is String && value.isNotEmpty) {
          return DateTime.parse(value);
        }
        if (value is int) {
          // Handle timestamp
          return DateTime.fromMillisecondsSinceEpoch(value);
        }
        return null;
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing DateTime: $value, error: $e');
        }
        return null;
      }
    }

    // Parse latitude/longitude với xử lý lỗi tốt hơn cho Android
    double? parsedLatitude;
    double? parsedLongitude;
    try {
      if (map['latitude'] != null) {
        final latValue = map['latitude'];
        if (latValue is num) {
          parsedLatitude = latValue.toDouble();
        } else if (latValue is String) {
          parsedLatitude = double.tryParse(latValue);
        }
      }
      if (map['longitude'] != null) {
        final lngValue = map['longitude'];
        if (lngValue is num) {
          parsedLongitude = lngValue.toDouble();
        } else if (lngValue is String) {
          parsedLongitude = double.tryParse(lngValue);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing latitude/longitude: $e');
      }
    }

    // Parse createdAt với fallback an toàn
    final createdAtValue = map['createdAt'];
    final parsedCreatedAt = safeParseDateTime(createdAtValue) ?? DateTime.now();

    final result = MessageModel(
      id: id,
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      content: map['content'] ?? '',
      imageUrl: map['imageUrl'],
      videoUrl: map['videoUrl'],
      audioUrl:
          map['audioUrl'] is String && (map['audioUrl'] as String).isNotEmpty
          ? map['audioUrl'] as String
          : null,
      audioDuration: map['audioDuration'] != null
          ? map['audioDuration'] is int
                ? map['audioDuration'] as int
                : (map['audioDuration'] is num
                      ? (map['audioDuration'] as num).toInt()
                      : int.tryParse(map['audioDuration'].toString()))
          : null,
      gifUrl: map['gifUrl'],
      isRead: map['isRead'] ?? false,
      conversationId: map['conversationId'],
      createdAt: parsedCreatedAt,
      isRecalled: map['isRecalled'] ?? false,
      recalledAt: safeParseDateTime(map['recalledAt']),
      isPinned: map['isPinned'] ?? false,
      pinnedAt: safeParseDateTime(map['pinnedAt']),
      reactions:
          (map['reactions'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              (value is List<dynamic>
                  ? value.map((e) => e.toString()).toList()
                  : []),
            ),
          ) ??
          {},
      status: map['status'] ?? 'sent',
      deliveredAt: safeParseDateTime(map['deliveredAt']),
      readAt: safeParseDateTime(map['readAt']),
      replyToMessageId: map['replyToMessageId'],
      replyToContent: map['replyToContent'],
      replyToSenderId: map['replyToSenderId'],
      replyToType: map['replyToType'],
      groupId: map['groupId'],
      latitude: parsedLatitude,
      longitude: parsedLongitude,
      locationAddress:
          map['locationAddress'] is String &&
              (map['locationAddress'] as String).isNotEmpty
          ? map['locationAddress'] as String
          : null,
      isLiveLocation: map['isLiveLocation'] is bool
          ? map['isLiveLocation'] as bool
          : (map['isLiveLocation'] == true || map['isLiveLocation'] == 'true'),
      locationExpiresAt: safeParseDateTime(map['locationExpiresAt']),
      deletedBy:
          (map['deletedBy'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );

    return result;
  }
}
