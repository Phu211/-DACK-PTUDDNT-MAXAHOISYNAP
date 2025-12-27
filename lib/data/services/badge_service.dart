import '../models/badge_model.dart';
import 'user_service.dart';
import 'analytics_service.dart';

class BadgeService {
  final UserService _userService = UserService();
  final AnalyticsService _analyticsService = AnalyticsService();

  /// Tính toán và trả về badges của user
  Future<List<BadgeModel>> getUserBadges(String userId) async {
    try {
      final badges = <BadgeModel>[];

      // Lấy thông tin user
      final userDoc = await _userService.getUserById(userId);
      if (userDoc == null) return badges;

      final now = DateTime.now();
      final accountAge = now.difference(userDoc.createdAt).inDays;

      // 1. Badge "Người mới" - tài khoản < 30 ngày
      if (accountAge < 30) {
        badges.add(
          BadgeModel(
            type: BadgeType.newUser,
            name: 'Người mới',
            description: 'Thành viên mới của Synap',
            icon: '🆕',
            earnedAt: userDoc.createdAt,
          ),
        );
      }

      // 2. Badge "Người tích cực" - đăng nhiều posts/stories
      final analytics = await _analyticsService.getUserAnalytics(
        userId,
        days: 7,
      );
      if (analytics.totalPosts >= 5 || userDoc.postsCount >= 20) {
        badges.add(
          BadgeModel(
            type: BadgeType.activeUser,
            name: 'Người tích cực',
            description: 'Đăng bài thường xuyên',
            icon: '⭐',
            earnedAt: now,
          ),
        );
      }

      // 3. Badge "Top creator" - nhiều tương tác
      if (analytics.totalLikes +
              analytics.totalComments +
              analytics.totalShares >=
          100) {
        badges.add(
          BadgeModel(
            type: BadgeType.topCreator,
            name: 'Top Creator',
            description: 'Nội dung được yêu thích',
            icon: '🏆',
            earnedAt: now,
          ),
        );
      }

      // 4. Badge "Nổi tiếng" - nhiều followers
      if (userDoc.followersCount >= 100) {
        badges.add(
          BadgeModel(
            type: BadgeType.popular,
            name: 'Nổi tiếng',
            description: 'Có nhiều người theo dõi',
            icon: '🌟',
            earnedAt: now,
          ),
        );
      }

      // 5. Badge "Early Adopter" - tài khoản cũ (< 90 ngày đầu)
      if (accountAge <= 90 && accountAge >= 30) {
        badges.add(
          BadgeModel(
            type: BadgeType.earlyAdopter,
            name: 'Người dùng sớm',
            description: 'Tham gia từ những ngày đầu',
            icon: '🚀',
            earnedAt: userDoc.createdAt,
          ),
        );
      }

      return badges;
    } catch (e) {
      return [];
    }
  }
}
