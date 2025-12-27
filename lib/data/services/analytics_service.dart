import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';
import '../../core/constants/app_constants.dart';

/// Model để lưu dữ liệu thống kê theo ngày
class DailyAnalytics {
  final DateTime date;
  final int views; // Tổng lượt xem (dùng likes+comments+shares như proxy)
  final int likes;
  final int comments;
  final int shares;
  final int saved; // Lượt lưu
  final int postsCount; // Số bài viết đăng trong ngày

  DailyAnalytics({
    required this.date,
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.saved = 0,
    this.postsCount = 0,
  });
}

/// Model để lưu tổng quan thống kê
class AnalyticsOverview {
  final int totalViews;
  final int totalLikes;
  final int totalComments;
  final int totalShares;
  final int totalSaved;
  final int totalPosts;
  final List<DailyAnalytics> dailyData;
  final List<PostModel> topPosts;

  AnalyticsOverview({
    this.totalViews = 0,
    this.totalLikes = 0,
    this.totalComments = 0,
    this.totalShares = 0,
    this.totalSaved = 0,
    this.totalPosts = 0,
    this.dailyData = const [],
    this.topPosts = const [],
  });
}

class AnalyticsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Lấy thống kê cho user trong khoảng thời gian
  Future<AnalyticsOverview> getUserAnalytics(
    String userId, {
    int days = 28,
  }) async {
    try {
      if (userId.isEmpty) {
        return AnalyticsOverview();
      }

      // Tính ngày bắt đầu
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: days));

      // Query tất cả posts của user (không filter theo date ở Firestore để tránh composite index)
      final postsSnapshot = await _firestore
          .collection(AppConstants.postsCollection)
          .where('userId', isEqualTo: userId)
          .get();

      // Filter theo date trên client và parse posts
      final posts = postsSnapshot.docs
          .map((doc) => PostModel.fromMap(doc.id, doc.data()))
          .where((post) => post.createdAt.isAfter(startDate))
          .toList();

      // Tính tổng quan
      int totalLikes = 0;
      int totalComments = 0;
      int totalShares = 0;
      int totalPosts = posts.length;

      // Tính tổng lượt lưu (cần query từ savedPosts collection)
      int totalSaved = 0;
      try {
        final savedSnapshot = await _firestore
            .collection(AppConstants.savedPostsCollection)
            .where('userId', isEqualTo: userId)
            .get();

        final savedPostIds = savedSnapshot.docs
            .map((doc) => doc.data()['postId'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();

        // Đếm số lượt lưu cho các posts của user này
        for (final post in posts) {
          if (savedPostIds.contains(post.id)) {
            totalSaved++;
          }
        }
      } catch (_) {
        // Ignore errors
      }

      // Tính toán theo ngày
      final dailyMap = <String, DailyAnalytics>{};
      for (int i = 0; i < days; i++) {
        final date = now.subtract(Duration(days: i));
        final dateKey = _getDateKey(date);
        dailyMap[dateKey] = DailyAnalytics(date: date);
      }

      // Phân bổ posts vào các ngày
      for (final post in posts) {
        final dateKey = _getDateKey(post.createdAt);
        final daily = dailyMap[dateKey];
        if (daily != null) {
          totalLikes += post.likesCount;
          totalComments += post.commentsCount;
          totalShares += post.sharesCount;

          dailyMap[dateKey] = DailyAnalytics(
            date: daily.date,
            views:
                daily.views +
                post.likesCount +
                post.commentsCount +
                post.sharesCount,
            likes: daily.likes + post.likesCount,
            comments: daily.comments + post.commentsCount,
            shares: daily.shares + post.sharesCount,
            saved: daily.saved,
            postsCount: daily.postsCount + 1,
          );
        }
      }

      // Sắp xếp dailyData theo ngày (cũ nhất trước)
      final dailyData = dailyMap.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      // Tính tổng views (dùng likes+comments+shares như proxy)
      final totalViews = totalLikes + totalComments + totalShares;

      // Lấy top 5 bài viết (sắp xếp theo tổng tương tác)
      final topPosts = posts.toList()
        ..sort((a, b) {
          final aScore = a.likesCount + a.commentsCount + a.sharesCount;
          final bScore = b.likesCount + b.commentsCount + b.sharesCount;
          return bScore.compareTo(aScore);
        });
      final top5Posts = topPosts.take(5).toList();

      return AnalyticsOverview(
        totalViews: totalViews,
        totalLikes: totalLikes,
        totalComments: totalComments,
        totalShares: totalShares,
        totalSaved: totalSaved,
        totalPosts: totalPosts,
        dailyData: dailyData,
        topPosts: top5Posts,
      );
    } catch (e) {
      throw Exception('Failed to get analytics: $e');
    }
  }

  /// Lấy key cho ngày (YYYY-MM-DD)
  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Gợi ý thời gian đăng tốt nhất dựa trên dữ liệu
  String getBestPostingTime(List<DailyAnalytics> dailyData) {
    if (dailyData.isEmpty) {
      return 'Chưa có dữ liệu';
    }

    // Tìm ngày có tổng tương tác cao nhất
    DailyAnalytics? bestDay;
    int maxEngagement = 0;

    for (final daily in dailyData) {
      final engagement = daily.likes + daily.comments + daily.shares;
      if (engagement > maxEngagement) {
        maxEngagement = engagement;
        bestDay = daily;
      }
    }

    if (bestDay == null) {
      return 'Chưa có dữ liệu';
    }

    // Format ngày
    final weekdays = [
      'Chủ nhật',
      'Thứ hai',
      'Thứ ba',
      'Thứ tư',
      'Thứ năm',
      'Thứ sáu',
      'Thứ bảy',
    ];
    final weekday = weekdays[bestDay.date.weekday % 7];
    final day = bestDay.date.day;
    final month = bestDay.date.month;

    return '$weekday, $day/$month';
  }
}
