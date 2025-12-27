import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';

class BlockService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Chặn người dùng
  Future<void> blockUser(String blockerId, String blockedId) async {
    try {
      if (blockerId.isEmpty || blockedId.isEmpty) {
        throw Exception('Invalid user IDs');
      }

      if (blockerId == blockedId) {
        throw Exception('Không thể chặn chính mình');
      }

      final docId = '${blockerId}_$blockedId';
      await _firestore
          .collection(AppConstants.blocksCollection)
          .doc(docId)
          .set({
            'blockerId': blockerId,
            'blockedId': blockedId,
            'createdAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Chặn người dùng thất bại: $e');
    }
  }

  /// Bỏ chặn người dùng
  Future<void> unblockUser(String blockerId, String blockedId) async {
    try {
      if (blockerId.isEmpty || blockedId.isEmpty) {
        throw Exception('Invalid user IDs');
      }

      final docId = '${blockerId}_$blockedId';
      await _firestore
          .collection(AppConstants.blocksCollection)
          .doc(docId)
          .delete();
    } catch (e) {
      throw Exception('Bỏ chặn người dùng thất bại: $e');
    }
  }

  /// Kiểm tra xem user có bị chặn không
  Future<bool> isBlocked({
    required String userId1,
    required String userId2,
  }) async {
    try {
      // Kiểm tra userId1 có chặn userId2 không
      final docId1 = '${userId1}_$userId2';
      final doc1 = await _firestore
          .collection(AppConstants.blocksCollection)
          .doc(docId1)
          .get();
      if (doc1.exists) return true;

      // Kiểm tra userId2 có chặn userId1 không
      final docId2 = '${userId2}_$userId1';
      final doc2 = await _firestore
          .collection(AppConstants.blocksCollection)
          .doc(docId2)
          .get();
      return doc2.exists;
    } catch (e) {
      return false;
    }
  }

  /// Kiểm tra xem user hiện tại có chặn user khác không
  Future<bool> isUserBlockedByMe({
    required String blockerId,
    required String blockedId,
  }) async {
    try {
      final docId = '${blockerId}_$blockedId';
      final doc = await _firestore
          .collection(AppConstants.blocksCollection)
          .doc(docId)
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Lấy danh sách người dùng bị chặn
  Stream<List<String>> getBlockedUsers(String blockerId) {
    return _firestore
        .collection(AppConstants.blocksCollection)
        .where('blockerId', isEqualTo: blockerId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => doc.data()['blockedId'] as String)
              .toList(),
        );
  }

  /// Lấy danh sách người dùng đã chặn tôi
  Stream<List<String>> getUsersWhoBlockedMe(String blockedId) {
    return _firestore
        .collection(AppConstants.blocksCollection)
        .where('blockedId', isEqualTo: blockedId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => doc.data()['blockerId'] as String)
              .toList(),
        );
  }
}
