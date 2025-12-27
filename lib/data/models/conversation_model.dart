class ConversationModel {
  final String id;
  final List<String> participantIds; // Danh sách user IDs tham gia
  final String lastMessageId; // ID của tin nhắn cuối cùng
  final String? lastMessageContent; // Nội dung tin nhắn cuối
  final String? lastMessageSenderId; // Người gửi tin nhắn cuối
  final String? lastMessageNonce; // Nonce để giải mã tin nhắn cuối
  final DateTime lastMessageTime; // Thời gian tin nhắn cuối
  final Map<String, int> unreadCounts; // Số tin nhắn chưa đọc cho mỗi user
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final DateTime? pinnedAt;
  final Map<String, String> nicknames; // userId -> nickname
  final String? groupId; // ID của nhóm nếu là conversation nhóm
  final String? type; // 'direct' hoặc 'group'
  final List<String> deletedBy; // Danh sách userId đã xóa conversation này

  ConversationModel({
    required this.id,
    required this.participantIds,
    this.lastMessageId = '',
    this.lastMessageContent,
    this.lastMessageSenderId,
    this.lastMessageNonce,
    required this.lastMessageTime,
    this.unreadCounts = const {},
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.pinnedAt,
    this.nicknames = const {},
    this.groupId,
    this.type = 'direct', // Mặc định là direct chat
    this.deletedBy = const [], // Mặc định không ai xóa
  });

  // Helper để lấy user ID của người còn lại trong cuộc trò chuyện 1-1
  String? getOtherUserId(String currentUserId) {
    if (participantIds.length != 2) return null;
    return participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => participantIds.first,
    );
  }

  // Helper để lấy số tin nhắn chưa đọc cho user hiện tại
  int getUnreadCount(String userId) {
    return unreadCounts[userId] ?? 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'participantIds': participantIds,
      'lastMessageId': lastMessageId,
      'lastMessageContent': lastMessageContent,
      'lastMessageSenderId': lastMessageSenderId,
      'lastMessageNonce': lastMessageNonce,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'unreadCounts': unreadCounts,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPinned': isPinned,
      'pinnedAt': pinnedAt?.toIso8601String(),
      'nicknames': nicknames,
      'groupId': groupId,
      'type': type,
      'deletedBy': deletedBy,
    };
  }

  factory ConversationModel.fromMap(String id, Map<String, dynamic> map) {
    return ConversationModel(
      id: id,
      participantIds: List<String>.from(map['participantIds'] ?? []),
      lastMessageId: map['lastMessageId'] ?? '',
      lastMessageContent: map['lastMessageContent'],
      lastMessageSenderId: map['lastMessageSenderId'],
      lastMessageNonce: map['lastMessageNonce'],
      lastMessageTime: DateTime.parse(
        map['lastMessageTime'] ?? DateTime.now().toIso8601String(),
      ),
      unreadCounts: Map<String, int>.from(map['unreadCounts'] ?? {}),
      createdAt: DateTime.parse(
        map['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        map['updatedAt'] ?? DateTime.now().toIso8601String(),
      ),
      isPinned: map['isPinned'] ?? false,
      pinnedAt: map['pinnedAt'] != null
          ? DateTime.parse(map['pinnedAt'])
          : null,
      nicknames: Map<String, String>.from(map['nicknames'] ?? {}),
      groupId: map['groupId'],
      type: map['type'] ?? 'direct',
      deletedBy: List<String>.from(map['deletedBy'] ?? []),
    );
  }
}
