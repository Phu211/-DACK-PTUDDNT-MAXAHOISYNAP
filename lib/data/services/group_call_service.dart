import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../models/group_call_model.dart';

class GroupCallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Tạo cuộc gọi nhóm mới
  Future<String> createGroupCall({
    required String groupId,
    required String creatorId,
    required List<String> participantIds,
    required bool isVideoCall,
  }) async {
    try {
      final now = DateTime.now();
      final participantStatus = <String, CallStatus>{};

      // Tất cả participants ban đầu đều ở trạng thái ringing
      for (final participantId in participantIds) {
        participantStatus[participantId] = CallStatus.ringing;
      }

      final groupCall = GroupCallModel(
        id: '',
        groupId: groupId,
        creatorId: creatorId,
        participantIds: participantIds,
        participantStatus: participantStatus,
        isVideoCall: isVideoCall,
        createdAt: now,
        status: 'active',
      );

      final docRef = await _firestore
          .collection(AppConstants.groupCallsCollection)
          .add(groupCall.toMap());

      return docRef.id;
    } catch (e) {
      throw Exception('Create group call failed: $e');
    }
  }

  // Lấy cuộc gọi nhóm đang active của một group
  Stream<GroupCallModel?> getActiveGroupCall(String groupId) {
    return _firestore
        .collection(AppConstants.groupCallsCollection)
        .where('groupId', isEqualTo: groupId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          return GroupCallModel.fromMap(
            snapshot.docs.first.id,
            snapshot.docs.first.data(),
          );
        });
  }

  // Tham gia cuộc gọi nhóm
  Future<void> joinGroupCall(String callId, String userId) async {
    try {
      await _firestore
          .collection(AppConstants.groupCallsCollection)
          .doc(callId)
          .update({
            'participantStatus.$userId': CallStatus.joined.name,
            'participantIds': FieldValue.arrayUnion([userId]),
          });
    } catch (e) {
      throw Exception('Join group call failed: $e');
    }
  }

  // Từ chối cuộc gọi nhóm
  Future<void> declineGroupCall(String callId, String userId) async {
    try {
      await _firestore
          .collection(AppConstants.groupCallsCollection)
          .doc(callId)
          .update({'participantStatus.$userId': CallStatus.declined.name});
    } catch (e) {
      throw Exception('Decline group call failed: $e');
    }
  }

  // Rời cuộc gọi nhóm
  Future<void> leaveGroupCall(String callId, String userId) async {
    try {
      final callDoc = await _firestore
          .collection(AppConstants.groupCallsCollection)
          .doc(callId)
          .get();

      if (!callDoc.exists) return;

      final data = callDoc.data()!;
      final participantIds = List<String>.from(data['participantIds'] ?? []);
      participantIds.remove(userId);

      // Nếu không còn ai trong cuộc gọi, kết thúc cuộc gọi
      if (participantIds.isEmpty) {
        await _firestore
            .collection(AppConstants.groupCallsCollection)
            .doc(callId)
            .update({
              'status': 'ended',
              'endedAt': DateTime.now().toIso8601String(),
              'participantStatus.$userId': CallStatus.left.name,
            });
      } else {
        await _firestore
            .collection(AppConstants.groupCallsCollection)
            .doc(callId)
            .update({
              'participantStatus.$userId': CallStatus.left.name,
              'participantIds': participantIds,
            });
      }
    } catch (e) {
      throw Exception('Leave group call failed: $e');
    }
  }

  // Kết thúc cuộc gọi nhóm (chỉ creator mới có thể)
  Future<void> endGroupCall(String callId, String userId) async {
    try {
      final callDoc = await _firestore
          .collection(AppConstants.groupCallsCollection)
          .doc(callId)
          .get();

      if (!callDoc.exists) {
        throw Exception('Group call not found');
      }

      final data = callDoc.data()!;
      final creatorId = data['creatorId'] as String;

      if (userId != creatorId) {
        throw Exception('Chỉ người tạo cuộc gọi mới có thể kết thúc');
      }

      await _firestore
          .collection(AppConstants.groupCallsCollection)
          .doc(callId)
          .update({
            'status': 'ended',
            'endedAt': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      throw Exception('End group call failed: $e');
    }
  }

  // Lấy thông tin cuộc gọi nhóm
  Future<GroupCallModel?> getGroupCall(String callId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.groupCallsCollection)
          .doc(callId)
          .get();

      if (!doc.exists) return null;

      return GroupCallModel.fromMap(doc.id, doc.data()!);
    } catch (e) {
      return null;
    }
  }
}

