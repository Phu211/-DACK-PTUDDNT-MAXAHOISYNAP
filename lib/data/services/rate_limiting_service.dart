import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service quản lý rate limiting để chống brute force và spam.
///
/// Giới hạn số lần thử đăng nhập, gửi email, và các hành động khác.
class RateLimitingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cấu hình rate limits
  static const int maxLoginAttemptsPerHour = 10;
  static const int maxEmailSendsPerDay = 20;
  static const int maxPasswordResetRequestsPerDay = 5;
  static const int maxAccountRecoveryAttemptsPerDay = 3;

  /// Kiểm tra xem có thể thử đăng nhập không.
  /// Trả về true nếu chưa vượt quá giới hạn.
  Future<bool> canAttemptLogin(String email) async {
    try {
      final now = DateTime.now();
      final oneHourAgo = now.subtract(const Duration(hours: 1));
      final oneHourAgoStr = oneHourAgo.toIso8601String();

      final attemptsSnapshot = await _firestore
          .collection('rateLimits')
          .doc('loginAttempts')
          .collection('attempts')
          .where('email', isEqualTo: email)
          .where('timestamp', isGreaterThanOrEqualTo: oneHourAgoStr)
          .get();

      return attemptsSnapshot.docs.length < maxLoginAttemptsPerHour;
    } catch (e) {
      debugPrint('Error checking login rate limit: $e');
      return true; // Cho phép nếu có lỗi
    }
  }

  /// Ghi lại một lần thử đăng nhập.
  Future<void> recordLoginAttempt(String email, {bool success = false}) async {
    try {
      await _firestore
          .collection('rateLimits')
          .doc('loginAttempts')
          .collection('attempts')
          .add({
        'email': email,
        'success': success,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Cleanup old attempts (older than 24 hours)
      await _cleanupOldAttempts('loginAttempts', hours: 24);
    } catch (e) {
      debugPrint('Error recording login attempt: $e');
    }
  }

  /// Kiểm tra xem có thể gửi email không.
  Future<bool> canSendEmail(String userId) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final startOfDayStr = startOfDay.toIso8601String();

      final sendsSnapshot = await _firestore
          .collection('rateLimits')
          .doc('emailSends')
          .collection('sends')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: startOfDayStr)
          .get();

      return sendsSnapshot.docs.length < maxEmailSendsPerDay;
    } catch (e) {
      debugPrint('Error checking email send rate limit: $e');
      return true;
    }
  }

  /// Ghi lại một lần gửi email.
  Future<void> recordEmailSend(String userId, String emailType) async {
    try {
      await _firestore
          .collection('rateLimits')
          .doc('emailSends')
          .collection('sends')
          .add({
        'userId': userId,
        'emailType': emailType,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Cleanup old sends (older than 7 days)
      await _cleanupOldAttempts('emailSends', hours: 24 * 7);
    } catch (e) {
      debugPrint('Error recording email send: $e');
    }
  }

  /// Kiểm tra xem có thể yêu cầu reset password không.
  Future<bool> canRequestPasswordReset(String email) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final startOfDayStr = startOfDay.toIso8601String();

      final requestsSnapshot = await _firestore
          .collection('rateLimits')
          .doc('passwordResetRequests')
          .collection('requests')
          .where('email', isEqualTo: email)
          .where('timestamp', isGreaterThanOrEqualTo: startOfDayStr)
          .get();

      return requestsSnapshot.docs.length < maxPasswordResetRequestsPerDay;
    } catch (e) {
      debugPrint('Error checking password reset rate limit: $e');
      return true;
    }
  }

  /// Ghi lại một lần yêu cầu reset password.
  Future<void> recordPasswordResetRequest(String email) async {
    try {
      await _firestore
          .collection('rateLimits')
          .doc('passwordResetRequests')
          .collection('requests')
          .add({
        'email': email,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Cleanup old requests (older than 7 days)
      await _cleanupOldAttempts('passwordResetRequests', hours: 24 * 7);
    } catch (e) {
      debugPrint('Error recording password reset request: $e');
    }
  }

  /// Cleanup các records cũ để tiết kiệm storage.
  Future<void> _cleanupOldAttempts(String collectionName,
      {required int hours}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(hours: hours));
      final cutoffStr = cutoff.toIso8601String();

      final oldDocs = await _firestore
          .collection('rateLimits')
          .doc(collectionName)
          .collection(collectionName == 'loginAttempts'
              ? 'attempts'
              : collectionName == 'emailSends'
                  ? 'sends'
                  : 'requests')
          .where('timestamp', isLessThan: cutoffStr)
          .limit(100) // Xóa từng batch để tránh timeout
          .get();

      if (oldDocs.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in oldDocs.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error cleaning up old attempts: $e');
    }
  }
}
