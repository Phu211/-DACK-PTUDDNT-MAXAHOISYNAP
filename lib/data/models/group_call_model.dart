class GroupCallModel {
  final String id;
  final String groupId;
  final String creatorId;
  final List<String> participantIds; // Danh sách người tham gia
  final Map<String, CallStatus> participantStatus; // userId -> status
  final bool isVideoCall;
  final DateTime createdAt;
  final DateTime? endedAt;
  final String status; // 'active', 'ended'

  GroupCallModel({
    required this.id,
    required this.groupId,
    required this.creatorId,
    this.participantIds = const [],
    this.participantStatus = const {},
    this.isVideoCall = false,
    required this.createdAt,
    this.endedAt,
    this.status = 'active',
  });

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'creatorId': creatorId,
      'participantIds': participantIds,
      'participantStatus': participantStatus.map((k, v) => MapEntry(k, v.name)),
      'isVideoCall': isVideoCall,
      'createdAt': createdAt.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'status': status,
    };
  }

  factory GroupCallModel.fromMap(String id, Map<String, dynamic> map) {
    final statusMap = <String, CallStatus>{};
    if (map['participantStatus'] != null) {
      (map['participantStatus'] as Map).forEach((k, v) {
        statusMap[k] = CallStatus.values.firstWhere(
          (e) => e.name == v,
          orElse: () => CallStatus.ringing,
        );
      });
    }

    return GroupCallModel(
      id: id,
      groupId: map['groupId'] ?? '',
      creatorId: map['creatorId'] ?? '',
      participantIds: List<String>.from(map['participantIds'] ?? []),
      participantStatus: statusMap,
      isVideoCall: map['isVideoCall'] ?? false,
      createdAt: DateTime.parse(map['createdAt']),
      endedAt: map['endedAt'] != null ? DateTime.parse(map['endedAt']) : null,
      status: map['status'] ?? 'active',
    );
  }
}

enum CallStatus {
  ringing, // Đang gọi
  joined, // Đã tham gia
  declined, // Từ chối
  left, // Rời cuộc gọi
}

