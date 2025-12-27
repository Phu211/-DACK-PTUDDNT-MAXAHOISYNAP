import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../models/notification_model.dart';
import '../models/user_model.dart';
import 'notification_service.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Simple in-memory cache to reduce repeated reads (e.g. chat list).
  // Cache is process-lifetime; safe for typical app sessions.
  static final Map<String, UserModel> _cache = <String, UserModel>{};
  static final Map<String, Future<UserModel?>> _inflight =
      <String, Future<UserModel?>>{};

  // Get user by ID
  Future<UserModel?> getUserById(String userId) async {
    final cached = _cache[userId];
    if (cached != null) return cached;
    final existing = _inflight[userId];
    if (existing != null) return existing;

    try {
      final future = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get()
          .then<UserModel?>((doc) {
            if (!doc.exists) return null;
            return UserModel.fromMap(doc.id, doc.data()!);
          });

      _inflight[userId] = future;
      final user = await future;
      _inflight.remove(userId);

      if (user != null) _cache[userId] = user;
      return user;
    } catch (e) {
      _inflight.remove(userId);
      return null;
    }
  }

  // Get multiple users by their IDs
  Future<List<UserModel>> getUsersByIds(List<String> userIds) async {
    if (userIds.isEmpty) return [];

    try {
      // Return cached immediately where possible
      final result = <UserModel>[];
      final missing = <String>[];
      for (final id in userIds) {
        final cached = _cache[id];
        if (cached != null) {
          result.add(cached);
        } else {
          missing.add(id);
        }
      }

      if (missing.isEmpty) return result;

      // Batch fetch missing ids in chunks of 10 (Firestore whereIn limit).
      for (var i = 0; i < missing.length; i += 10) {
        final batch = missing.sublist(
          i,
          i + 10 > missing.length ? missing.length : i + 10,
        );
        final snapshot = await _firestore
            .collection(AppConstants.usersCollection)
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in snapshot.docs) {
          final user = UserModel.fromMap(doc.id, doc.data());
          _cache[user.id] = user;
          result.add(user);
        }
      }

      return result;
    } catch (e) {
      return [];
    }
  }

  // Get users stream (for search)
  Stream<List<UserModel>> searchUsers(String query) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .where('username', isGreaterThanOrEqualTo: query)
        .where('username', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(20)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => UserModel.fromMap(doc.id, doc.data()))
              .toList();
        });
  }

  // Get user by username
  Future<UserModel?> getUserByUsername(String username) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      final user = UserModel.fromMap(doc.id, doc.data());
      _cache[user.id] = user;
      return user;
    } catch (e) {
      return null;
    }
  }

  // Get user by email
  Future<UserModel?> getUserByEmail(String email) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      final user = UserModel.fromMap(doc.id, doc.data());
      _cache[user.id] = user;
      return user;
    } catch (e) {
      return null;
    }
  }

  // Follow user
  Future<void> followUser(String followerId, String followingId) async {
    try {
      await _firestore
          .collection(AppConstants.followsCollection)
          .doc('${followerId}_$followingId')
          .set({
            'followerId': followerId,
            'followingId': followingId,
            'createdAt': DateTime.now().toIso8601String(),
          });

      // Update followers count
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(followingId)
          .update({'followersCount': FieldValue.increment(1)});

      // Update following count
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(followerId)
          .update({'followingCount': FieldValue.increment(1)});

      // 🔔 App notification: someone followed you
      try {
        final notificationService = NotificationService();
        await notificationService.createNotification(
          NotificationModel(
            id: '',
            userId: followingId,
            actorId: followerId,
            type: NotificationType.follow,
            createdAt: DateTime.now(),
          ),
        );
      } catch (_) {
        // Ignore notification failures to keep follow UX smooth
      }
    } catch (e) {
      throw Exception('Follow user failed: $e');
    }
  }

  // Unfollow user
  Future<void> unfollowUser(String followerId, String followingId) async {
    try {
      await _firestore
          .collection(AppConstants.followsCollection)
          .doc('${followerId}_$followingId')
          .delete();

      // Update followers count
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(followingId)
          .update({'followersCount': FieldValue.increment(-1)});

      // Update following count
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(followerId)
          .update({'followingCount': FieldValue.increment(-1)});
    } catch (e) {
      throw Exception('Unfollow user failed: $e');
    }
  }

  // Check if user is following
  Future<bool> isFollowing(String followerId, String followingId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.followsCollection)
          .doc('${followerId}_$followingId')
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }
}
