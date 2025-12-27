import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/user_interaction_model.dart';
import '../models/post_model.dart';
import '../models/video_model.dart';
import '../models/page_model.dart';
import '../models/product_model.dart';
import 'friend_service.dart';
import 'group_service.dart';
// Removed firestore_service and user_service imports to break circular dependency and reduce unused code

/// Service để tính toán recommendations dựa trên nhiều tín hiệu
class RecommendationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FriendService _friendService = FriendService();
  final GroupService _groupService = GroupService();
  // Removed FirestoreService and UserService to break circular dependency and reduce unused code

  /// Tính điểm recommendation cho một item
  Future<double> calculateRecommendationScore({
    required String userId,
    required String targetId,
    required String targetType,
  }) async {
    double score = 0.0;

    // 1. Tín hiệu từ tương tác trực tiếp
    final interactions = await _getUserInteractions(userId, targetId, targetType);
    for (final interaction in interactions) {
      score += interaction.weight;
      
      // Bonus cho tương tác gần đây (decay theo thời gian)
      final daysSince = DateTime.now().difference(interaction.timestamp).inDays;
      final recencyBonus = daysSince < 1 ? 2.0 : (daysSince < 7 ? 1.5 : (daysSince < 30 ? 1.0 : 0.5));
      score *= recencyBonus;
    }

    // 2. Tín hiệu từ bạn bè
    final friendIds = await _friendService.getFriends(userId);
    if (targetType == 'user') {
      // Nếu là user, kiểm tra bạn chung
      final mutualFriends = await _getMutualFriends(userId, targetId);
      score += mutualFriends.length * 2.0;
    } else {
      // Nếu là content, kiểm tra bạn bè đã tương tác
      final friendInteractions = await _getFriendInteractions(friendIds, targetId, targetType);
      score += friendInteractions * 1.5;
    }

    // 3. Tín hiệu từ độ phổ biến
    final popularityScore = await _getPopularityScore(targetId, targetType);
    score += popularityScore * 0.3;

    // 4. Tín hiệu từ nội dung tương tự đã tương tác
    final similarContentScore = await _getSimilarContentScore(userId, targetId, targetType);
    score += similarContentScore * 0.5;

    // 5. Tín hiệu từ vị trí địa lý (nếu có)
    // TODO: Implement location-based recommendations

    // 6. Tín hiệu từ thời gian (trending content)
    final trendingScore = await _getTrendingScore(targetId, targetType);
    score += trendingScore * 0.2;

    return score;
  }

  /// Gợi ý bạn bè - chỉ dựa vào bạn chung
  Future<List<UserModel>> recommendFriends(String userId, {int limit = 10}) async {
    try {
      // Lấy danh sách bạn bè hiện tại
      final friendIds = await _friendService.getFriends(userId);
      friendIds.add(userId); // Thêm chính mình để loại trừ

      // Lấy tất cả bạn bè của bạn bè (bạn của bạn)
      final Map<String, int> mutualFriendsCount = {};
      
      // Nếu có bạn bè, tìm bạn chung
      if (friendIds.length > 1) { // Có ít nhất 1 bạn bè (ngoài chính mình)
        for (final friendId in friendIds) {
          if (friendId == userId) continue; // Bỏ qua chính mình
          
          try {
            final friendsOfFriend = await _friendService.getFriends(friendId);
            
            for (final candidateId in friendsOfFriend) {
              // Bỏ qua nếu là chính mình, đã là bạn bè, hoặc đã có trong danh sách
              if (candidateId == userId || friendIds.contains(candidateId)) continue;
              
              // Đếm số bạn chung
              mutualFriendsCount.update(
                candidateId,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
            }
          } catch (e) {
            // Bỏ qua nếu không lấy được bạn bè của bạn bè (có thể do permission)
            continue;
          }
        }
      }

      // Nếu không có bạn chung hoặc chưa có bạn bè, lấy random users
      if (mutualFriendsCount.isEmpty) {
        // Lấy tất cả users (trừ chính mình và bạn bè)
        final allUsersSnapshot = await _firestore
            .collection(AppConstants.usersCollection)
            .limit(100)
            .get();
        
        final candidateIds = <String>[];
        for (var doc in allUsersSnapshot.docs) {
          final candidateId = doc.id;
          if (candidateId != userId && !friendIds.contains(candidateId)) {
            candidateIds.add(candidateId);
          }
        }
        
        // Shuffle và lấy limit users
        candidateIds.shuffle();
        final topCandidateIds = candidateIds.take(limit).toList();
        
        final users = <UserModel>[];
        for (final candidateId in topCandidateIds) {
          try {
            final userDoc = await _firestore
                .collection(AppConstants.usersCollection)
                .doc(candidateId)
                .get();
            
            if (userDoc.exists && userDoc.data() != null) {
              final user = UserModel.fromMap(candidateId, userDoc.data()!);
              users.add(user);
            }
          } catch (e) {
            // Bỏ qua nếu không lấy được user
            continue;
          }
        }
        
        return users;
      }

      // Sort theo số bạn chung (nhiều nhất trước)
      final sortedCandidates = mutualFriendsCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Lấy top users và fetch thông tin từ Firestore
      final topCandidateIds = sortedCandidates.take(limit).map((e) => e.key).toList();
      
      final users = <UserModel>[];
      for (final candidateId in topCandidateIds) {
        try {
          final userDoc = await _firestore
              .collection(AppConstants.usersCollection)
              .doc(candidateId)
              .get();
          
          if (userDoc.exists && userDoc.data() != null) {
            final user = UserModel.fromMap(candidateId, userDoc.data()!);
            users.add(user);
          }
        } catch (e) {
          // Bỏ qua nếu không lấy được user
          continue;
        }
      }

      return users;
    } catch (e) {
      // Log lỗi để debug
      print('Error in recommendFriends: $e');
      // Trả về empty list nếu có lỗi
      return [];
    }
  }

  /// Gợi ý nhóm
  Future<List<GroupModel>> recommendGroups(String userId, {int limit = 10}) async {
    final userGroups = await _groupService.getUserGroups(userId).first;
    final userGroupIds = userGroups.map((g) => g.id).toList();

    final allGroups = await _firestore
        .collection(AppConstants.groupsCollection)
        .where('isPublic', isEqualTo: true)
        .limit(100)
        .get();

    final candidates = <_ScoredGroup>[];

    for (var doc in allGroups.docs) {
      final group = GroupModel.fromMap(doc.id, doc.data());
      if (userGroupIds.contains(group.id)) continue;

      final score = await calculateRecommendationScore(
        userId: userId,
        targetId: group.id,
        targetType: 'group',
      );

      // Bonus cho nhóm có nhiều bạn bè tham gia
      final friendIds = await _friendService.getFriends(userId);
      final friendsInGroup = group.memberIds.where((id) => friendIds.contains(id)).length;
      final finalScore = score + (friendsInGroup * 3.0);

      candidates.add(_ScoredGroup(group: group, score: finalScore));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(limit).map((sg) => sg.group).toList();
  }

  /// Gợi ý posts (cho News Feed ranking)
  Future<List<PostModel>> recommendPosts(String userId, List<PostModel> posts) async {
    final scoredPosts = <_ScoredPost>[];

    for (final post in posts) {
      final score = await calculateRecommendationScore(
        userId: userId,
        targetId: post.id,
        targetType: 'post',
      );

      scoredPosts.add(_ScoredPost(post: post, score: score));
    }

    scoredPosts.sort((a, b) => b.score.compareTo(a.score));
    return scoredPosts.map((sp) => sp.post).toList();
  }

  /// Gợi ý videos/Reels
  Future<List<VideoModel>> recommendVideos(String userId, {int limit = 20}) async {
    final allVideos = await _firestore
        .collection(AppConstants.videosCollection)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();

    final candidates = <_ScoredVideo>[];

    for (var doc in allVideos.docs) {
      final video = VideoModel.fromMap(doc.id, doc.data());
      
      final score = await calculateRecommendationScore(
        userId: userId,
        targetId: video.id,
        targetType: 'video',
      );

      // Bonus cho video có nhiều views và engagement
      final engagementScore = (video.viewsCount * 0.1) + 
                             (video.likesCount * 0.5) + 
                             (video.commentsCount * 0.3);
      final finalScore = score + engagementScore;

      candidates.add(_ScoredVideo(video: video, score: finalScore));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(limit).map((sv) => sv.video).toList();
  }

  /// Gợi ý Pages
  Future<List<PageModel>> recommendPages(String userId, {int limit = 10}) async {
    final allPages = await _firestore
        .collection(AppConstants.pagesCollection)
        .limit(100)
        .get();

    final candidates = <_ScoredPage>[];

    for (var doc in allPages.docs) {
      final page = PageModel.fromMap(doc.id, doc.data());
      
      final score = await calculateRecommendationScore(
        userId: userId,
        targetId: page.id,
        targetType: 'page',
      );

      // Bonus cho page phổ biến và verified
      final popularityScore = (page.followersCount * 0.01) + 
                              (page.likesCount * 0.01);
      final verifiedBonus = page.isVerified ? 5.0 : 0.0;
      final finalScore = score + popularityScore + verifiedBonus;

      candidates.add(_ScoredPage(page: page, score: finalScore));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(limit).map((sp) => sp.page).toList();
  }

  /// Gợi ý sản phẩm Marketplace
  Future<List<ProductModel>> recommendProducts(String userId, {int limit = 20}) async {
    final allProducts = await _firestore
        .collection(AppConstants.productsCollection)
        .where('isAvailable', isEqualTo: true)
        .limit(100)
        .get();

    final candidates = <_ScoredProduct>[];

    for (var doc in allProducts.docs) {
      final product = ProductModel.fromMap(doc.id, doc.data());
      
      final score = await calculateRecommendationScore(
        userId: userId,
        targetId: product.id,
        targetType: 'product',
      );

      // Bonus cho sản phẩm có nhiều views và likes
      final engagementScore = (product.viewsCount * 0.1) + 
                             (product.likesCount * 0.5);
      final finalScore = score + engagementScore;

      candidates.add(_ScoredProduct(product: product, score: finalScore));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(limit).map((sp) => sp.product).toList();
  }

  /// Lưu tương tác của user
  Future<void> recordInteraction(UserInteractionModel interaction) async {
    try {
      await _firestore
          .collection(AppConstants.userInteractionsCollection)
          .add(interaction.toMap());
    } catch (e) {
      // Silent fail - không ảnh hưởng UX
    }
  }

  // Helper methods

  Future<List<UserInteractionModel>> _getUserInteractions(
    String userId,
    String targetId,
    String targetType,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.userInteractionsCollection)
          .where('userId', isEqualTo: userId)
          .where('targetId', isEqualTo: targetId)
          .where('targetType', isEqualTo: targetType)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      return snapshot.docs
          .map((doc) => UserInteractionModel.fromMap(doc.data()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> _getMutualFriends(String userId1, String userId2) async {
    final friends1 = await _friendService.getFriends(userId1);
    final friends2 = await _friendService.getFriends(userId2);
    return friends1.where((id) => friends2.contains(id)).toList();
  }

  /// Public method để lấy bạn chung (dùng trong UI)
  Future<List<String>> getMutualFriends(String userId1, String userId2) async {
    return _getMutualFriends(userId1, userId2);
  }

  Future<double> _getFriendInteractions(
    List<String> friendIds,
    String targetId,
    String targetType,
  ) async {
    if (friendIds.isEmpty) return 0.0;

    try {
      final snapshot = await _firestore
          .collection(AppConstants.userInteractionsCollection)
          .where('targetId', isEqualTo: targetId)
          .where('targetType', isEqualTo: targetType)
          .where('userId', whereIn: friendIds.take(10).toList())
          .get();

      return snapshot.docs.length * 1.0;
    } catch (e) {
      return 0.0;
    }
  }

  Future<double> _getPopularityScore(String targetId, String targetType) async {
    try {
      final interactions = await _firestore
          .collection(AppConstants.userInteractionsCollection)
          .where('targetId', isEqualTo: targetId)
          .where('targetType', isEqualTo: targetType)
          .get();

      return interactions.docs.length * 0.1;
    } catch (e) {
      return 0.0;
    }
  }

  Future<double> _getSimilarContentScore(
    String userId,
    String targetId,
    String targetType,
  ) async {
    // TODO: Implement content similarity (hashtags, categories, etc.)
    return 0.0;
  }

  Future<double> _getTrendingScore(String targetId, String targetType) async {
    try {
      final now = DateTime.now();
      final last24h = now.subtract(const Duration(hours: 24));

      final allInteractions = await _firestore
          .collection(AppConstants.userInteractionsCollection)
          .where('targetId', isEqualTo: targetId)
          .where('targetType', isEqualTo: targetType)
          .get();

      // Filter in code to avoid index requirement
      final recentInteractions = allInteractions.docs.where((doc) {
        final timestamp = DateTime.parse(doc.data()['timestamp']);
        return timestamp.isAfter(last24h);
      }).toList();

      return recentInteractions.length * 0.5;
    } catch (e) {
      return 0.0;
    }
  }
}

// Helper classes for scoring
class _ScoredGroup {
  final GroupModel group;
  final double score;

  _ScoredGroup({required this.group, required this.score});
}

class _ScoredPost {
  final PostModel post;
  final double score;

  _ScoredPost({required this.post, required this.score});
}

class _ScoredVideo {
  final VideoModel video;
  final double score;

  _ScoredVideo({required this.video, required this.score});
}

class _ScoredPage {
  final PageModel page;
  final double score;

  _ScoredPage({required this.page, required this.score});
}

class _ScoredProduct {
  final ProductModel product;
  final double score;

  _ScoredProduct({required this.product, required this.score});
}


