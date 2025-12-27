import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import 'login_history_service.dart';
import 'account_lockout_service.dart';
import 'push_gateway_service.dart';

/// Service phát hiện hoạt động đáng ngờ và gửi cảnh báo.
///
/// Lưu các hoạt động đáng ngờ vào `users/{uid}/suspiciousActivities/{activityId}` với:
/// - activityType: loại hoạt động (newDevice, multipleFailedLogins, passwordChanged, etc.)
/// - detectedAt: thời gian phát hiện
/// - details: thông tin chi tiết
/// - isResolved: đã được xử lý/chấp nhận chưa
///
/// **Email Notifications:**
/// Để gửi email tự động khi có hoạt động đáng ngờ mới:
/// 1. Cài Firebase Extension "Trigger Email" trong Firebase Console
/// 2. Cấu hình collection path: `users/{userId}/suspiciousActivities/{activityId}`
/// 3. Setup SMTP (Gmail/SendGrid/Mailgun)
/// 4. Xem chi tiết trong file `FIREBASE_EMAIL_SETUP.md`
///
/// Extension sẽ tự động gửi email khi có document mới được tạo.

/// Service phát hiện hoạt động đáng ngờ và gửi cảnh báo.
///
/// Lưu các hoạt động đáng ngờ vào `users/{uid}/suspiciousActivities/{activityId}` với:
/// - activityType: loại hoạt động (newDevice, multipleFailedLogins, passwordChanged, etc.)
/// - detectedAt: thời gian phát hiện
/// - details: thông tin chi tiết
/// - isResolved: đã được xử lý/chấp nhận chưa
class SuspiciousActivityService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LoginHistoryService _loginHistoryService = LoginHistoryService();
  final AccountLockoutService _lockoutService = AccountLockoutService();

  /// Phát hiện và ghi lại hoạt động đáng ngờ khi đăng nhập.
  Future<void> detectSuspiciousLogin(String email, {bool? isNewDevice}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // 1. Kiểm tra đăng nhập từ thiết bị mới
      // Nếu isNewDevice chưa được truyền vào, kiểm tra từ login history
      bool newDevice = isNewDevice ?? false;
      if (isNewDevice == null) {
        // Kiểm tra xem có thiết bị mới không bằng cách xem login history gần đây
        final recentHistory = await _loginHistoryService.getLoginHistory(limit: 1);
        if (recentHistory.isNotEmpty) {
          newDevice = recentHistory.first['isNewDevice'] == true;
        }
      }
      
      if (newDevice) {
        await _recordActivity(
          user.uid,
          'newDevice',
          'Đăng nhập từ thiết bị mới',
        );
      }

      // 2. Kiểm tra nhiều lần đăng nhập sai gần đây
      final remainingAttempts = await _lockoutService.getRemainingAttempts(
        email,
      );
      if (remainingAttempts <= 2 && remainingAttempts > 0) {
        await _recordActivity(
          user.uid,
          'multipleFailedLogins',
          'Nhiều lần đăng nhập sai gần đây (còn $remainingAttempts lần thử)',
        );
      }
    } catch (e) {
      debugPrint('Error detecting suspicious login: $e');
    }
  }

  /// Phát hiện khi mật khẩu bị thay đổi.
  Future<void> detectPasswordChange() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _recordActivity(
        user.uid,
        'passwordChanged',
        'Mật khẩu đã được thay đổi',
      );
    } catch (e) {
      debugPrint('Error detecting password change: $e');
    }
  }

  /// Phát hiện khi email bị thay đổi.
  Future<void> detectEmailChange(String oldEmail, String newEmail) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _recordActivity(
        user.uid,
        'emailChanged',
        'Email đã được thay đổi từ $oldEmail sang $newEmail',
      );
    } catch (e) {
      debugPrint('Error detecting email change: $e');
    }
  }

  /// Ghi lại hoạt động đáng ngờ vào Firestore.
  Future<void> _recordActivity(
    String userId,
    String activityType,
    String details,
  ) async {
    try {
      final activityRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('suspiciousActivities')
          .doc();

      await activityRef.set({
        'activityType': activityType,
        'details': details,
        'detectedAt': DateTime.now().toIso8601String(),
        'isResolved': false,
      });

      // Gửi thông báo trong app
      await _sendActivityAlert(userId, activityType, details);
    } catch (e) {
      debugPrint('Error recording suspicious activity: $e');
    }
  }

  /// Gửi cảnh báo về hoạt động đáng ngờ.
  Future<void> _sendActivityAlert(
    String userId,
    String activityType,
    String details,
  ) async {
    try {
      String message;
      switch (activityType) {
        case 'newDevice':
          message =
              'Cảnh báo: Đăng nhập từ thiết bị mới. Nếu không phải bạn, vui lòng đổi mật khẩu ngay.';
          break;
        case 'multipleFailedLogins':
          message =
              'Cảnh báo: Nhiều lần đăng nhập sai. Nếu không phải bạn, vui lòng kiểm tra tài khoản.';
          break;
        case 'passwordChanged':
          message =
              'Thông báo: Mật khẩu đã được thay đổi. Nếu không phải bạn, vui lòng liên hệ hỗ trợ.';
          break;
        case 'emailChanged':
          message =
              'Thông báo: Email đã được thay đổi. Nếu không phải bạn, vui lòng liên hệ hỗ trợ ngay.';
          break;
        default:
          message =
              'Cảnh báo: Phát hiện hoạt động đáng ngờ trong tài khoản của bạn.';
      }

      debugPrint(
        'Suspicious activity detected for user $userId: $activityType - $message',
      );

      // Gửi email qua SendGrid (backend server)
      try {
        await PushGatewayService.instance.notifySecurityAlert(
          userId: userId,
          activityType: activityType,
          details: details,
        );
      } catch (e) {
        debugPrint('Error sending email via SendGrid: $e');
        // Không throw để không chặn luồng chính
      }
    } catch (e) {
      debugPrint('Error sending activity alert: $e');
    }
  }

  /// Lấy danh sách hoạt động đáng ngờ (mới nhất trước).
  Future<List<Map<String, dynamic>>> getSuspiciousActivities({
    int limit = 50,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .collection('suspiciousActivities')
          .get();

      final activities = snapshot.docs
          .map((d) => ({'id': d.id, ...d.data()}))
          .toList(growable: false);

      // Sort theo detectedAt (mới nhất trước)
      activities.sort((a, b) {
        final aTime = a['detectedAt'] as String?;
        final bTime = b['detectedAt'] as String?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        try {
          return DateTime.parse(bTime).compareTo(DateTime.parse(aTime));
        } catch (_) {
          return 0;
        }
      });

      return activities.take(limit).toList();
    } catch (e) {
      debugPrint('Error getting suspicious activities: $e');
      return [];
    }
  }

  /// Đánh dấu hoạt động đã được xử lý/chấp nhận.
  Future<void> markActivityAsResolved(String activityId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .collection('suspiciousActivities')
          .doc(activityId)
          .update({'isResolved': true});
    } catch (e) {
      debugPrint('Error marking activity as resolved: $e');
    }
  }

  /// Xóa hoạt động đáng ngờ cũ hơn N ngày.
  Future<void> cleanupOldActivities({int daysToKeep = 90}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));

      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .collection('suspiciousActivities')
          .get();

      final batch = _firestore.batch();
      int deletedCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final detectedAtStr = data['detectedAt'] as String?;
        if (detectedAtStr != null) {
          try {
            final detectedAt = DateTime.parse(detectedAtStr);
            if (detectedAt.isBefore(cutoffDate)) {
              batch.delete(doc.reference);
              deletedCount++;
            }
          } catch (_) {
            // ignore
          }
        }
      }

      if (deletedCount > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error cleaning up old activities: $e');
    }
  }
}
