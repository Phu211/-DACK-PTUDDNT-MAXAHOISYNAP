import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../models/friend_request_model.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';

class FriendService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Simple in-memory cache to avoid repeated reads (e.g. feed ranking).
  static final Map<String, List<String>> _friendsCache =
      <String, List<String>>{};
  static final Map<String, Future<List<String>>> _friendsInflight =
      <String, Future<List<String>>>{};

  static void _invalidateFriendsCache(String userId) {
    _friendsCache.remove(userId);
    _friendsInflight.remove(userId);
  }

  // Send friend request
  Future<void> sendFriendRequest(String senderId, String receiverId) async {
    try {
      // Check if request already exists
      final existingRequest = await _firestore
          .collection(AppConstants.friendRequestsCollection)
          .where('senderId', isEqualTo: senderId)
          .where('receiverId', isEqualTo: receiverId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingRequest.docs.isNotEmpty) {
        throw Exception('Friend request already sent');
      }

      // Check if receiver already sent a pending request to sender
      final reverseRequest = await _firestore
          .collection(AppConstants.friendRequestsCollection)
          .where('senderId', isEqualTo: receiverId)
          .where('receiverId', isEqualTo: senderId)
          .where('status', isEqualTo: FriendRequestStatus.pending.name)
          .limit(1)
          .get();

      if (reverseRequest.docs.isNotEmpty) {
        throw Exception(
          'Người này đã gửi lời mời, hãy chấp nhận trong danh sách yêu cầu',
        );
      }

      // Check if already friends
      final isFriend = await isFriendWith(senderId, receiverId);
      if (isFriend) {
        throw Exception('Already friends');
      }

      await _firestore.collection(AppConstants.friendRequestsCollection).add({
        'senderId': senderId,
        'receiverId': receiverId,
        'status': FriendRequestStatus.pending.name,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // Create notification
      final notificationService = NotificationService();
      await notificationService.createNotification(
        NotificationModel(
          id: '',
          userId: receiverId,
          actorId: senderId,
          type: NotificationType.friendRequest,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      throw Exception('Send friend request failed: $e');
    }
  }

  // Check if there is any pending friend request between two users
  Future<bool> hasPendingRequestBetween(String userId1, String userId2) async {
    try {
      final pendingFromUser1 = await _firestore
          .collection(AppConstants.friendRequestsCollection)
          .where('senderId', isEqualTo: userId1)
          .where('receiverId', isEqualTo: userId2)
          .where('status', isEqualTo: FriendRequestStatus.pending.name)
          .limit(1)
          .get();

      if (pendingFromUser1.docs.isNotEmpty) {
        return true;
      }

      final pendingFromUser2 = await _firestore
          .collection(AppConstants.friendRequestsCollection)
          .where('senderId', isEqualTo: userId2)
          .where('receiverId', isEqualTo: userId1)
          .where('status', isEqualTo: FriendRequestStatus.pending.name)
          .limit(1)
          .get();

      return pendingFromUser2.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Get pending friend request from a specific sender to receiver
  Future<FriendRequestModel?> getPendingRequest(
    String senderId,
    String receiverId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.friendRequestsCollection)
          .where('senderId', isEqualTo: senderId)
          .where('receiverId', isEqualTo: receiverId)
          .where('status', isEqualTo: FriendRequestStatus.pending.name)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        return FriendRequestModel.fromMap(doc.id, doc.data());
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Cancel a pending friend request sent by the current user
  Future<void> cancelFriendRequest(String senderId, String receiverId) async {
    try {
      final pendingRequest = await getPendingRequest(senderId, receiverId);

      if (pendingRequest == null) {
        throw Exception('Không tìm thấy lời mời kết bạn đang chờ');
      }

      await _firestore
          .collection(AppConstants.friendRequestsCollection)
          .doc(pendingRequest.id)
          .delete();
    } catch (e) {
      throw Exception('Cancel friend request failed: $e');
    }
  }

  // Accept friend request
  Future<void> acceptFriendRequest(
    String requestId,
    String senderId,
    String receiverId,
  ) async {
    try {
      // Update request status
      await _firestore
          .collection(AppConstants.friendRequestsCollection)
          .doc(requestId)
          .update({
            'status': FriendRequestStatus.accepted.name,
            'updatedAt': DateTime.now().toIso8601String(),
          });

      // Sort userIds để đảm bảo document ID consistent
      final sortedIds = [senderId, receiverId]..sort();
      final docId1 = '${sortedIds[0]}_${sortedIds[1]}';
      final docId2 = '${sortedIds[1]}_${sortedIds[0]}';

      // Create bidirectional friendship với document ID consistent
      await Future.wait([
        _firestore
            .collection(AppConstants.friendsCollection)
            .doc(docId1)
            .set({
              'userId1': sortedIds[0],
              'userId2': sortedIds[1],
              'createdAt': DateTime.now().toIso8601String(),
            }),
        _firestore
            .collection(AppConstants.friendsCollection)
            .doc(docId2)
            .set({
              'userId1': sortedIds[1],
              'userId2': sortedIds[0],
              'createdAt': DateTime.now().toIso8601String(),
            }),
      ]);

      // Invalidate caches (friend list changed)
      _invalidateFriendsCache(senderId);
      _invalidateFriendsCache(receiverId);

      // Update friend counts
      await Future.wait([
        _firestore
            .collection(AppConstants.usersCollection)
            .doc(senderId)
            .update({'followersCount': FieldValue.increment(1)}),
        _firestore
            .collection(AppConstants.usersCollection)
            .doc(receiverId)
            .update({'followersCount': FieldValue.increment(1)}),
      ]);
    } catch (e) {
      throw Exception('Accept friend request failed: $e');
    }
  }

  // Reject friend request
  Future<void> rejectFriendRequest(String requestId) async {
    try {
      await _firestore
          .collection(AppConstants.friendRequestsCollection)
          .doc(requestId)
          .update({
            'status': FriendRequestStatus.rejected.name,
            'updatedAt': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      throw Exception('Reject friend request failed: $e');
    }
  }

  // Check if two users are friends
  Future<bool> isFriendWith(String userId1, String userId2) async {
    try {
      // Sort userIds để đảm bảo document ID consistent
      final sortedIds = [userId1, userId2]..sort();
      final docId = '${sortedIds[0]}_${sortedIds[1]}';
      
      final doc = await _firestore
          .collection(AppConstants.friendsCollection)
          .doc(docId)
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  // Get friend requests for a user
  Stream<List<FriendRequestModel>> getFriendRequests(String userId) {
    return _firestore
        .collection(AppConstants.friendRequestsCollection)
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => FriendRequestModel.fromMap(doc.id, doc.data()))
              .toList();

          // Sắp xếp mới nhất trước trên client để tránh cần composite index
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        })
        .handleError((error) {
          // Handle permission errors gracefully (user may have logged out)
          if (error.toString().contains('permission-denied') || 
              error.toString().contains('permission denied')) {
            return <FriendRequestModel>[];
          }
          // Re-throw other errors
          throw error;
        });
  }

  // Get friends list (Future - for one-time fetch)
  Future<List<String>> getFriends(String userId) async {
    final cached = _friendsCache[userId];
    if (cached != null) return cached;
    final existing = _friendsInflight[userId];
    if (existing != null) return await existing;

    try {
      final future = () async {
        final friends1 = await _firestore
            .collection(AppConstants.friendsCollection)
            .where('userId1', isEqualTo: userId)
            .get();

        final friends2 = await _firestore
            .collection(AppConstants.friendsCollection)
            .where('userId2', isEqualTo: userId)
            .get();

        final friendIds = <String>{};
        for (var doc in friends1.docs) {
          final userId2 = doc.data()['userId2'] as String?;
          if (userId2 != null) friendIds.add(userId2);
        }
        for (var doc in friends2.docs) {
          final userId1 = doc.data()['userId1'] as String?;
          if (userId1 != null) friendIds.add(userId1);
        }

        return friendIds.toList();
      }();

      _friendsInflight[userId] = future;
      final result = await future;
      _friendsInflight.remove(userId);
      _friendsCache[userId] = result;
      return result;
    } catch (e) {
      _friendsInflight.remove(userId);
      print('Error getting friends: $e');
      return [];
    }
  }

  // Get friends list as Stream (for real-time updates)
  Stream<List<String>> getFriendsStream(String userId) {
    final controller = StreamController<List<String>>();
    final friendIds1 = <String>{};
    final friendIds2 = <String>{};
    StreamSubscription? subscription1;
    StreamSubscription? subscription2;

    void emitResult() {
      final allFriendIds = <String>{}
        ..addAll(friendIds1)
        ..addAll(friendIds2);
      final result = allFriendIds.toList();
      _friendsCache[userId] = result;
      if (!controller.isClosed) {
        controller.add(result);
      }
    }

    // Stream 1: userId1 == userId
    subscription1 = _firestore
        .collection(AppConstants.friendsCollection)
        .where('userId1', isEqualTo: userId)
        .snapshots()
        .listen(
      (snapshot) {
        friendIds1.clear();
        for (var doc in snapshot.docs) {
          final userId2 = doc.data()['userId2'] as String?;
          if (userId2 != null) friendIds1.add(userId2);
        }
        emitResult();
      },
      onError: (error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
    );

    // Stream 2: userId2 == userId
    subscription2 = _firestore
        .collection(AppConstants.friendsCollection)
        .where('userId2', isEqualTo: userId)
        .snapshots()
        .listen(
      (snapshot) {
        friendIds2.clear();
        for (var doc in snapshot.docs) {
          final userId1 = doc.data()['userId1'] as String?;
          if (userId1 != null) friendIds2.add(userId1);
        }
        emitResult();
      },
      onError: (error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
    );

    // Clean up when stream is cancelled
    controller.onCancel = () {
      subscription1?.cancel();
      subscription2?.cancel();
    };

    return controller.stream;
  }

  // Unfriend
  Future<void> unfriend(String userId1, String userId2) async {
    try {
      // Sort userIds để đảm bảo document ID consistent
      final sortedIds = [userId1, userId2]..sort();
      final docId1 = '${sortedIds[0]}_${sortedIds[1]}';
      final docId2 = '${sortedIds[1]}_${sortedIds[0]}';
      
      await Future.wait([
        _firestore
            .collection(AppConstants.friendsCollection)
            .doc(docId1)
            .delete(),
        _firestore
            .collection(AppConstants.friendsCollection)
            .doc(docId2)
            .delete(),
      ]);

      // Update friend counts
      await Future.wait([
        _firestore.collection(AppConstants.usersCollection).doc(userId1).update(
          {'followersCount': FieldValue.increment(-1)},
        ),
        _firestore.collection(AppConstants.usersCollection).doc(userId2).update(
          {'followersCount': FieldValue.increment(-1)},
        ),
      ]);

      // Invalidate caches (friend list changed)
      _invalidateFriendsCache(userId1);
      _invalidateFriendsCache(userId2);
    } catch (e) {
      throw Exception('Unfriend failed: $e');
    }
  }

  // Get mutual friends count between two users
  Future<int> getMutualFriendsCount(String userId1, String userId2) async {
    try {
      final friends1 = await getFriends(userId1);
      final friends2 = await getFriends(userId2);

      final mutualFriends = friends1
          .where((id) => friends2.contains(id))
          .toList();
      return mutualFriends.length;
    } catch (e) {
      return 0;
    }
  }
}
