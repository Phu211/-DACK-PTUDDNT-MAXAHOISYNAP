import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import 'friend_service.dart';

class FeedControlService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Mark post as interested
  Future<void> markPostAsInterested(String postId, String userId) async {
    try {
      await _firestore
          .collection('feedPreferences')
          .doc('${userId}_$postId')
          .set({
        'userId': userId,
        'postId': postId,
        'type': 'interested',
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Mark post as interested failed: $e');
    }
  }

  // Mark post as not interested
  Future<void> markPostAsNotInterested(String postId, String userId) async {
    try {
      await _firestore
          .collection('feedPreferences')
          .doc('${userId}_$postId')
          .set({
        'userId': userId,
        'postId': postId,
        'type': 'notInterested',
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Mark post as not interested failed: $e');
    }
  }

  // Unfollow user (hide all posts from user)
  Future<void> unfollowUser(String userId, String unfollowedUserId) async {
    try {
      await _firestore
          .collection(AppConstants.hiddenPostsCollection)
          .doc('unfollow_${unfollowedUserId}_$userId')
          .set({
        'userId': userId,
        'hiddenUserId': unfollowedUserId,
        'type': 'unfollow',
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Unfollow user failed: $e');
    }
  }

  // Follow user again (undo unfollow)
  Future<void> followUser(String userId, String followedUserId) async {
    try {
      await _firestore
          .collection(AppConstants.hiddenPostsCollection)
          .doc('unfollow_${followedUserId}_$userId')
          .delete();
    } catch (e) {
      throw Exception('Follow user failed: $e');
    }
  }

  // Check if user is unfollowed
  Future<bool> isUserUnfollowed(String userId, String otherUserId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.hiddenPostsCollection)
          .doc('unfollow_${otherUserId}_$userId')
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  // Enable post notifications
  Future<void> enablePostNotifications(String postId, String userId) async {
    try {
      await _firestore
          .collection('postNotifications')
          .doc('${postId}_$userId')
          .set({
        'postId': postId,
        'userId': userId,
        'enabled': true,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Enable post notifications failed: $e');
    }
  }

  // Disable post notifications
  Future<void> disablePostNotifications(String postId, String userId) async {
    try {
      await _firestore
          .collection('postNotifications')
          .doc('${postId}_$userId')
          .delete();
    } catch (e) {
      throw Exception('Disable post notifications failed: $e');
    }
  }

  // Check if post notifications are enabled
  Future<bool> isPostNotificationEnabled(String postId, String userId) async {
    try {
      final doc = await _firestore
          .collection('postNotifications')
          .doc('${postId}_$userId')
          .get();
      return doc.exists && (doc.data()?['enabled'] == true);
    } catch (e) {
      return false;
    }
  }

  // Get list of unfollowed users
  Future<List<Map<String, dynamic>>> getUnfollowedUsers(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.hiddenPostsCollection)
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'unfollow')
          .get();

      final unfollowedUsers = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        unfollowedUsers.add({
          'hiddenUserId': data['hiddenUserId'] as String? ?? '',
          'createdAt': DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
        });
      }
      
      return unfollowedUsers;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting unfollowed users: $e');
      }
      return [];
    }
  }

  // Get user's feed preferences
  Future<Map<String, dynamic>> getFeedPreferences(String userId) async {
    try {
      final interestedSnapshot = await _firestore
          .collection('feedPreferences')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'interested')
          .get();

      final notInterestedSnapshot = await _firestore
          .collection('feedPreferences')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'notInterested')
          .get();

      final unfollowedSnapshot = await _firestore
          .collection(AppConstants.hiddenPostsCollection)
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'unfollow')
          .get();

      return {
        'interestedPostIds': interestedSnapshot.docs
            .map((doc) => doc.data()['postId'] as String)
            .toList(),
        'notInterestedPostIds': notInterestedSnapshot.docs
            .map((doc) => doc.data()['postId'] as String)
            .toList(),
        'unfollowedUserIds': unfollowedSnapshot.docs
            .map((doc) => doc.data()['hiddenUserId'] as String)
            .toList(),
      };
    } catch (e) {
      throw Exception('Get feed preferences failed: $e');
    }
  }

  // Get explanation for why user sees a post
  Future<Map<String, dynamic>> getPostExplanation(
    String postId,
    String userId,
    String postAuthorId,
  ) async {
    try {
      final reasons = <String>[];
      final friendService = FriendService();
      final friendIds = await friendService.getFriends(userId);
      final isFriend = friendIds.contains(postAuthorId);

      if (isFriend) {
        reasons.add('Bạn bè của bạn');
      }

      // Check interactions
      final interactions = await _firestore
          .collection(AppConstants.userInteractionsCollection)
          .where('userId', isEqualTo: userId)
          .where('targetUserId', isEqualTo: postAuthorId)
          .limit(5)
          .get();

      if (interactions.docs.isNotEmpty) {
        reasons.add('Bạn đã tương tác với ${interactions.docs.length} bài viết của họ');
      }

      // Check if post has high engagement
      final likesCount = await _firestore
          .collection(AppConstants.likesCollection)
          .where('postId', isEqualTo: postId)
          .get();

      if (likesCount.docs.length > 10) {
        reasons.add('Bài viết có nhiều lượt tương tác');
      }

      // Check if user is interested in similar content
      final interestedPosts = await _firestore
          .collection('feedPreferences')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'interested')
          .limit(1)
          .get();

      if (interestedPosts.docs.isNotEmpty) {
        reasons.add('Bạn đã quan tâm đến nội dung tương tự');
      }

      if (reasons.isEmpty) {
        reasons.add('Hệ thống gợi ý bài viết này dựa trên hoạt động của bạn');
      }

      return {
        'reasons': reasons,
        'isFriend': isFriend,
        'interactionCount': interactions.docs.length,
        'likesCount': likesCount.docs.length,
      };
    } catch (e) {
      return {
        'reasons': ['Hệ thống gợi ý bài viết này dựa trên hoạt động của bạn'],
        'isFriend': false,
        'interactionCount': 0,
        'likesCount': 0,
      };
    }
  }
}


