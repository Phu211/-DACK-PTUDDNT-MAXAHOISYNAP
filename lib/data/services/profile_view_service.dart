import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';

class ProfileViewModel {
  final String id;
  final String profileUserId; // User được xem
  final String viewerUserId; // User xem profile
  final DateTime viewedAt;

  ProfileViewModel({
    required this.id,
    required this.profileUserId,
    required this.viewerUserId,
    required this.viewedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'profileUserId': profileUserId,
      'viewerUserId': viewerUserId,
      'viewedAt': viewedAt.toIso8601String(),
    };
  }

  factory ProfileViewModel.fromMap(String id, Map<String, dynamic> map) {
    try {
      return ProfileViewModel(
        id: id,
        profileUserId: map['profileUserId'] ?? '',
        viewerUserId: map['viewerUserId'] ?? '',
        viewedAt: map['viewedAt'] is String
            ? DateTime.parse(map['viewedAt'])
            : (map['viewedAt'] as Timestamp).toDate(),
      );
    } catch (e) {
      // Fallback nếu có lỗi parse
      if (kDebugMode) {
        print('ProfileViewModel: Error parsing fromMap: $e, map: $map');
      }
      rethrow;
    }
  }
}

class ProfileViewService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Ghi lại lượt xem profile
  Future<void> recordProfileView(
    String profileUserId,
    String viewerUserId,
  ) async {
    try {
      // Không ghi lại nếu user xem chính profile của mình
      if (profileUserId == viewerUserId) {
        if (kDebugMode) {
          print('ProfileViewService: Skipping - user viewing own profile');
        }
        return;
      }

      if (kDebugMode) {
        print(
          'ProfileViewService: Recording view - profileUserId: $profileUserId, viewerUserId: $viewerUserId',
        );
      }

      // Kiểm tra xem đã xem trong 24h chưa (tránh spam)
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      // Query theo viewerUserId (user có thể đọc profileViews của chính mình)
      // Sau đó filter theo profileUserId và viewedAt ở client
      final existingViews = await _firestore
          .collection(AppConstants.profileViewsCollection)
          .where('viewerUserId', isEqualTo: viewerUserId)
          .limit(100) // Lấy nhiều hơn để filter ở client
          .get();

      if (kDebugMode) {
        print(
          'ProfileViewService: Found ${existingViews.docs.length} existing views for viewerUserId: $viewerUserId',
        );
      }

      // Filter profileUserId và viewedAt ở client side
      final recentViews = existingViews.docs
          .map((doc) {
            try {
              return ProfileViewModel.fromMap(doc.id, doc.data());
            } catch (e) {
              if (kDebugMode) {
                print('ProfileViewService: Error parsing view ${doc.id}: $e');
              }
              return null;
            }
          })
          .whereType<ProfileViewModel>()
          .where(
            (view) =>
                view.profileUserId == profileUserId &&
                view.viewedAt.isAfter(yesterday),
          )
          .toList();

      if (recentViews.isNotEmpty) {
        if (kDebugMode) {
          print(
            'ProfileViewService: Skipping - already viewed in last 24h (${recentViews.length} recent views)',
          );
        }
        return; // Đã xem trong 24h
      }

      // Ghi lại lượt xem mới
      final docRef = await _firestore
          .collection(AppConstants.profileViewsCollection)
          .add({
        'profileUserId': profileUserId,
        'viewerUserId': viewerUserId,
        'viewedAt': DateTime.now().toIso8601String(),
      });

      if (kDebugMode) {
        print(
          'ProfileViewService: Successfully recorded profile view with id: ${docRef.id}',
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('ProfileViewService: Failed to record profile view: $e');
        print('ProfileViewService: Stack trace: $stackTrace');
      }
    }
  }

  /// Lấy số lượt xem profile trong 7 ngày
  Future<int> getProfileViewsCount(String userId, {int days = 7}) async {
    try {
      final startDate = DateTime.now().subtract(Duration(days: days));
      final snapshot = await _firestore
          .collection(AppConstants.profileViewsCollection)
          .where('profileUserId', isEqualTo: userId)
          .get();

      if (kDebugMode) {
        print(
          'ProfileViewService: getProfileViewsCount - Found ${snapshot.docs.length} total views for userId: $userId',
        );
      }

      // Filter viewedAt ở client side để tránh cần composite index
      final views = snapshot.docs
          .map((doc) {
            try {
              return ProfileViewModel.fromMap(doc.id, doc.data());
            } catch (e) {
              if (kDebugMode) {
                print('ProfileViewService: Error parsing view in getProfileViewsCount: $e');
              }
              return null;
            }
          })
          .whereType<ProfileViewModel>()
          .where((view) => view.viewedAt.isAfter(startDate))
          .toList();

      if (kDebugMode) {
        print(
          'ProfileViewService: getProfileViewsCount - Filtered to ${views.length} views in last $days days',
        );
      }

      return views.length;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('ProfileViewService: Error in getProfileViewsCount: $e');
        print('ProfileViewService: Stack trace: $stackTrace');
      }
      return 0;
    }
  }

  /// Lấy danh sách người đã xem profile (7 ngày gần đây)
  Stream<List<ProfileViewModel>> getRecentProfileViews(String userId) {
    final startDate = DateTime.now().subtract(const Duration(days: 7));
    return _firestore
        .collection(AppConstants.profileViewsCollection)
        .where('profileUserId', isEqualTo: userId)
        .limit(200) // Lấy nhiều hơn để bù cho việc filter và sort ở client
        .snapshots()
        .map((snapshot) {
          if (kDebugMode) {
            print(
              'ProfileViewService: getRecentProfileViews - Received ${snapshot.docs.length} views for userId: $userId',
            );
          }

          // Filter viewedAt và sort ở client side để tránh cần composite index
          final allViews = snapshot.docs
              .map((doc) {
                try {
                  return ProfileViewModel.fromMap(doc.id, doc.data());
                } catch (e) {
                  if (kDebugMode) {
                    print(
                      'ProfileViewService: Error parsing view in getRecentProfileViews: $e',
                    );
                  }
                  return null;
                }
              })
              .whereType<ProfileViewModel>()
              .where(
                (view) => view.viewedAt.isAfter(startDate),
              ) // Filter ở client
              .toList();

          if (kDebugMode) {
            print(
              'ProfileViewService: getRecentProfileViews - Filtered to ${allViews.length} views in last 7 days',
            );
          }

          // Sort theo viewedAt descending ở client
          allViews.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));

          // Giới hạn số lượng sau khi filter và sort
          final result = allViews.take(50).toList();

          if (kDebugMode) {
            print(
              'ProfileViewService: getRecentProfileViews - Returning ${result.length} views',
            );
          }

          return result;
        });
  }
}
