import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service quản lý khôi phục tài khoản qua email.
///
/// Cho phép user reset password khi quên mật khẩu.
/// Sử dụng Firebase Auth's sendPasswordResetEmail với rate limiting.
class AccountRecoveryService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cấu hình
  static const int maxResetRequestsPerDay = 5; // Tối đa 5 lần yêu cầu reset/ngày

  /// Gửi email reset password qua Firebase Auth.
  /// Có rate limiting để chống spam.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      // Kiểm tra rate limiting
      final canRequest = await _checkRateLimit(email);
      if (!canRequest) {
        throw Exception(
            'Bạn đã yêu cầu reset mật khẩu quá nhiều lần. Vui lòng thử lại sau 24 giờ.');
      }

      // Gửi email reset qua Firebase Auth
      await _auth.sendPasswordResetEmail(email: email);

      // Ghi lại request để rate limiting
      await _recordResetRequest(email);
    } on FirebaseAuthException catch (e) {
      // Không tiết lộ email không tồn tại (bảo mật)
      if (e.code == 'user-not-found') {
        // Giả vờ thành công để không tiết lộ thông tin
        return;
      }
      rethrow;
    } catch (e) {
      debugPrint('Error sending password reset email: $e');
      rethrow;
    }
  }

  /// Kiểm tra rate limiting cho reset requests.
  Future<bool> _checkRateLimit(String email) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final startOfDayStr = startOfDay.toIso8601String();

      final requestsSnapshot = await _firestore
          .collection('passwordResetRequests')
          .where('email', isEqualTo: email)
          .where('requestedAt', isGreaterThanOrEqualTo: startOfDayStr)
          .get();

      return requestsSnapshot.docs.length < maxResetRequestsPerDay;
    } catch (e) {
      debugPrint('Error checking rate limit: $e');
      return true; // Cho phép nếu có lỗi
    }
  }

  /// Ghi lại reset request để rate limiting.
  Future<void> _recordResetRequest(String email) async {
    try {
      await _firestore.collection('passwordResetRequests').add({
        'email': email,
        'requestedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error recording reset request: $e');
    }
  }

}
