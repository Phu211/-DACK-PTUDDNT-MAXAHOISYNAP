import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../models/group_model.dart';
import 'message_service.dart';

class GroupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MessageService _messageService = MessageService();

  // Simple in-memory cache to avoid repeated group reads in chat list.
  static final Map<String, GroupModel> _cache = <String, GroupModel>{};
  static final Map<String, Future<GroupModel?>> _inflight =
      <String, Future<GroupModel?>>{};

  // Create a group
  Future<String> createGroup(GroupModel group) async {
    try {
      // Đảm bảo creatorId có trong memberIds và memberRoles
      final memberIds = List<String>.from(group.memberIds);
      if (!memberIds.contains(group.creatorId)) {
        memberIds.add(group.creatorId);
      }

      final memberRoles = Map<String, GroupRole>.from(group.memberRoles);
      memberRoles[group.creatorId] = GroupRole.admin;

      final groupData = group.toMap();
      groupData['memberIds'] = memberIds;
      groupData['memberRoles'] = memberRoles.map((k, v) => MapEntry(k, v.name));

      final docRef = await _firestore
          .collection(AppConstants.groupsCollection)
          .add(groupData);

      return docRef.id;
    } catch (e) {
      throw Exception('Create group failed: $e');
    }
  }

  // Get group by ID
  Future<GroupModel?> getGroup(String groupId) async {
    final cached = _cache[groupId];
    if (cached != null) return cached;
    final existing = _inflight[groupId];
    if (existing != null) return existing;

    try {
      final future = _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .get()
          .then<GroupModel?>((doc) {
            if (!doc.exists) return null;
            return GroupModel.fromMap(doc.id, doc.data()!);
          });

      _inflight[groupId] = future;
      final group = await future;
      _inflight.remove(groupId);

      if (group != null) _cache[groupId] = group;
      return group;
    } catch (e) {
      _inflight.remove(groupId);
      return null;
    }
  }

  // Get groups user is member of (chỉ lấy nhóm đăng bài)
  Stream<List<GroupModel>> getUserGroups(String userId) {
    return _firestore
        .collection(AppConstants.groupsCollection)
        .where('memberIds', arrayContains: userId)
        .where('type', isEqualTo: 'post') // Chỉ lấy nhóm đăng bài
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GroupModel.fromMap(doc.id, doc.data()))
              .toList();
        });
  }

  // Get chat groups user is member of (nhóm nhắn tin)
  Stream<List<GroupModel>> getUserChatGroups(String userId) {
    return _firestore
        .collection(AppConstants.groupsCollection)
        .where('memberIds', arrayContains: userId)
        .where('type', isEqualTo: 'chat') // Chỉ lấy nhóm nhắn tin
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GroupModel.fromMap(doc.id, doc.data()))
              .toList();
        });
  }

  // Join group
  Future<void> joinGroup(String groupId, String userId) async {
    try {
      await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .update({
            'memberIds': FieldValue.arrayUnion([userId]),
            'memberRoles.$userId': GroupRole.member.name,
            'updatedAt': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      throw Exception('Join group failed: $e');
    }
  }

  // Leave group
  Future<void> leaveGroup(String groupId, String userId) async {
    try {
      await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .update({
            'memberIds': FieldValue.arrayRemove([userId]),
            'memberRoles.$userId': FieldValue.delete(),
            'updatedAt': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      throw Exception('Leave group failed: $e');
    }
  }

  // Add member to group (only admin/creator can do this)
  Future<void> addMember(
    String groupId,
    String adminId,
    String memberId,
  ) async {
    try {
      // Kiểm tra quyền admin
      final groupDoc = await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .get();

      if (!groupDoc.exists) {
        throw Exception('Group not found');
      }

      final groupData = groupDoc.data()!;
      final creatorId = groupData['creatorId'] as String;
      final memberRoles = Map<String, dynamic>.from(
        groupData['memberRoles'] ?? {},
      );
      final adminRole = memberRoles[adminId] as String?;
      final memberIds = List<String>.from(groupData['memberIds'] ?? []);

      // Chỉ creator hoặc admin mới có quyền thêm thành viên
      if (adminId != creatorId && adminRole != 'admin') {
        throw Exception('Bạn không có quyền thêm thành viên vào nhóm');
      }

      // Kiểm tra member đã có trong group chưa
      if (memberIds.contains(memberId)) {
        throw Exception('Người này đã là thành viên của nhóm');
      }

      // Thêm thành viên vào group
      await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .update({
            'memberIds': FieldValue.arrayUnion([memberId]),
            'memberRoles.$memberId': GroupRole.member.name,
            'updatedAt': DateTime.now().toIso8601String(),
          });

      // Cập nhật conversation để thêm member vào participantIds
      await _messageService.addMemberToGroupConversation(groupId, memberId);
    } catch (e) {
      throw Exception('Add member failed: $e');
    }
  }

  // Remove member from group (only admin/creator can do this)
  Future<void> removeMember(
    String groupId,
    String adminId,
    String memberId,
  ) async {
    try {
      // Kiểm tra quyền admin
      final groupDoc = await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .get();

      if (!groupDoc.exists) {
        throw Exception('Group not found');
      }

      final groupData = groupDoc.data()!;
      final creatorId = groupData['creatorId'] as String;
      final memberRoles = Map<String, dynamic>.from(
        groupData['memberRoles'] ?? {},
      );
      final adminRole = memberRoles[adminId] as String?;

      // Chỉ creator hoặc admin mới có quyền xóa thành viên
      if (adminId != creatorId && adminRole != 'admin') {
        throw Exception('Bạn không có quyền xóa thành viên khỏi nhóm');
      }

      // Không cho phép xóa creator
      if (memberId == creatorId) {
        throw Exception('Không thể xóa người tạo nhóm');
      }

      // Không cho phép tự xóa chính mình (dùng leaveGroup thay vì)
      if (adminId == memberId) {
        throw Exception('Vui lòng sử dụng chức năng rời nhóm');
      }

      // Xóa thành viên khỏi group
      await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .update({
            'memberIds': FieldValue.arrayRemove([memberId]),
            'memberRoles.$memberId': FieldValue.delete(),
            'updatedAt': DateTime.now().toIso8601String(),
          });

      // Cập nhật conversation để xóa member khỏi participantIds
      await _messageService.removeMemberFromGroupConversation(
        groupId,
        memberId,
      );
    } catch (e) {
      throw Exception('Remove member failed: $e');
    }
  }

  // Update group settings (only admin/creator can do this)
  Future<void> updateGroup(
    String groupId, {
    String? name,
    String? description,
    String? coverUrl,
    bool? isPublic,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': DateTime.now().toIso8601String(),
      };

      if (name != null) {
        updates['name'] = name;
      }
      if (description != null) {
        updates['description'] = description;
      }
      if (coverUrl != null) {
        updates['coverUrl'] = coverUrl;
      }
      if (isPublic != null) {
        updates['isPublic'] = isPublic;
      }

      await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .update(updates);
    } catch (e) {
      throw Exception('Update group failed: $e');
    }
  }

  // Update member role
  Future<void> updateMemberRole(
    String groupId,
    String userId,
    GroupRole role,
  ) async {
    try {
      await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .update({
            'memberRoles.$userId': role.name,
            'updatedAt': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      throw Exception('Update member role failed: $e');
    }
  }

  // Search groups (chỉ tìm nhóm đăng bài)
  Stream<List<GroupModel>> searchGroups(String query) {
    if (query.isEmpty) {
      return Stream.value([]);
    }

    final lowerQuery = query.toLowerCase();

    return _firestore
        .collection(AppConstants.groupsCollection)
        .where('isPublic', isEqualTo: true)
        .where('type', isEqualTo: 'post') // Chỉ tìm nhóm đăng bài
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GroupModel.fromMap(doc.id, doc.data()))
              .where(
                (group) =>
                    group.name.toLowerCase().contains(lowerQuery) ||
                    (group.description?.toLowerCase().contains(lowerQuery) ??
                        false),
              )
              .toList();
        });
  }
}
